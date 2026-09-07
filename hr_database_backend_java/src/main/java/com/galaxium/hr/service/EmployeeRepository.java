package com.galaxium.hr.service;

import com.galaxium.hr.model.Employee;
import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.locks.ReadWriteLock;
import java.util.concurrent.locks.ReentrantReadWriteLock;

/**
 * Service repository to read and write the Markdown pipe-table database.
 * Thread-safe with a ReadWriteLock.
 */
@ApplicationScoped
public class EmployeeRepository {

    @ConfigProperty(name = "hr.database.file-path", defaultValue = "data/employees.md")
    String filePath;

    private final ReadWriteLock lock = new ReentrantReadWriteLock();

    public List<Employee> getAll() {
        lock.readLock().lock();
        try {
            return readEmployees();
        } finally {
            lock.readLock().unlock();
        }
    }

    public Optional<Employee> getById(String id) {
        lock.readLock().lock();
        try {
            return readEmployees().stream()
                    .filter(emp -> id.equals(emp.id))
                    .findFirst();
        } finally {
            lock.readLock().unlock();
        }
    }

    public Employee create(Employee newEmp) {
        lock.writeLock().lock();
        try {
            List<Employee> list = readEmployees();
            int maxId = 0;
            for (Employee emp : list) {
                try {
                    int idVal = Integer.parseInt(emp.id.trim());
                    if (idVal > maxId) {
                        maxId = idVal;
                    }
                } catch (NumberFormatException ignored) {}
            }
            String newId = String.valueOf(maxId + 1);
            newEmp.id = newId;
            list.add(newEmp);
            writeEmployees(list);
            return newEmp;
        } finally {
            lock.writeLock().unlock();
        }
    }

    public Optional<Employee> update(String id, Employee updatedEmp) {
        lock.writeLock().lock();
        try {
            List<Employee> list = readEmployees();
            for (int i = 0; i < list.size(); i++) {
                if (id.equals(list.get(i).id)) {
                    updatedEmp.id = id;
                    list.set(i, updatedEmp);
                    writeEmployees(list);
                    return Optional.of(updatedEmp);
                }
            }
            return Optional.empty();
        } finally {
            lock.writeLock().unlock();
        }
    }

    public boolean delete(String id) {
        lock.writeLock().lock();
        try {
            List<Employee> list = readEmployees();
            boolean removed = list.removeIf(emp -> id.equals(emp.id));
            if (removed) {
                writeEmployees(list);
            }
            return removed;
        } finally {
            lock.writeLock().unlock();
        }
    }

    private List<Employee> readEmployees() {
        Path path = Paths.get(filePath);
        if (!Files.exists(path)) {
            throw new RuntimeException("Error reading employee database: File " + filePath + " does not exist. The database file may be corrupted or missing. Please check if the data/employees.md file exists and has the correct format.");
        }

        try {
            List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
            List<Employee> employees = new ArrayList<>();

            for (String line : lines) {
                String trimmedLine = line.trim();
                if (!trimmedLine.startsWith("|")) {
                    continue;
                }

                // Split line by '|'
                String[] parts = trimmedLine.split("\\|", -1);
                if (parts.length < 8) {
                    continue; // invalid table row
                }

                String empId = parts[1].trim();
                // Check if this is the header row or the separator row
                if (empId.equalsIgnoreCase("id") || empId.startsWith("-")) {
                    continue;
                }

                String firstName = parts[2].trim();
                String lastName = parts[3].trim();
                String department = parts[4].trim();
                String position = parts[5].trim();
                String hireDate = parts[6].trim();
                String salary = parts[7].trim();

                employees.add(new Employee(empId, firstName, lastName, department, position, hireDate, salary));
            }
            return employees;
        } catch (IOException e) {
            throw new RuntimeException("Error reading employee database: " + e.getMessage() + ". The database file may be corrupted or missing. Please check if the data/employees.md file exists and has the correct format.", e);
        }
    }

    private void writeEmployees(List<Employee> employees) {
        Path path = Paths.get(filePath);
        try {
            // Ensure parent directory exists
            Path parentDir = path.getParent();
            if (parentDir != null && !Files.exists(parentDir)) {
                Files.createDirectories(parentDir);
            }

            StringBuilder sb = new StringBuilder();
            sb.append("# Galaxium Travels HR Database\n\n## Employees\n\n");
            sb.append("| id | first_name | last_name | department | position | hire_date | salary |\n");
            sb.append("|---|---|---|---|---|---|---|\n");
            for (Employee emp : employees) {
                sb.append(String.format("|%s|%s|%s|%s|%s|%s|%s|\n",
                        emp.id, emp.firstName, emp.lastName, emp.department, emp.position, emp.hireDate, emp.salary));
            }

            Files.writeString(path, sb.toString(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new RuntimeException("Error writing to employee database: " + e.getMessage() + ". The system may not have write permissions to the data directory, or the data/employees.md file may be locked by another process.", e);
        }
    }
}
