package com.galaxium.hr.service;

import com.galaxium.hr.model.Job;
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
 * Service repository to read and write the jobs Markdown pipe-table database.
 * Thread-safe with a ReadWriteLock.
 */
@ApplicationScoped
public class JobRepository {

    @ConfigProperty(name = "hr.jobs.file-path", defaultValue = "data/jobs.md")
    String filePath;

    private final ReadWriteLock lock = new ReentrantReadWriteLock();

    public List<Job> getAll() {
        lock.readLock().lock();
        try {
            return readJobs();
        } finally {
            lock.readLock().unlock();
        }
    }

    public Optional<Job> getById(String id) {
        lock.readLock().lock();
        try {
            return readJobs().stream()
                    .filter(job -> id.equals(job.id))
                    .findFirst();
        } finally {
            lock.readLock().unlock();
        }
    }

    public Job create(Job newJob) {
        lock.writeLock().lock();
        try {
            List<Job> list = readJobs();
            int maxId = 0;
            for (Job job : list) {
                try {
                    int idVal = Integer.parseInt(job.id.trim());
                    if (idVal > maxId) {
                        maxId = idVal;
                    }
                } catch (NumberFormatException ignored) {}
            }
            newJob.id = String.valueOf(maxId + 1);
            list.add(newJob);
            writeJobs(list);
            return newJob;
        } finally {
            lock.writeLock().unlock();
        }
    }

    public Optional<Job> update(String id, Job updatedJob) {
        lock.writeLock().lock();
        try {
            List<Job> list = readJobs();
            for (int i = 0; i < list.size(); i++) {
                if (id.equals(list.get(i).id)) {
                    updatedJob.id = id;
                    list.set(i, updatedJob);
                    writeJobs(list);
                    return Optional.of(updatedJob);
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
            List<Job> list = readJobs();
            boolean removed = list.removeIf(job -> id.equals(job.id));
            if (removed) {
                writeJobs(list);
            }
            return removed;
        } finally {
            lock.writeLock().unlock();
        }
    }

    private List<Job> readJobs() {
        Path path = Paths.get(filePath);
        if (!Files.exists(path)) {
            throw new RuntimeException("Error reading job database: File " + filePath + " does not exist. The database file may be corrupted or missing. Please check if the data/jobs.md file exists and has the correct format.");
        }

        try {
            List<String> lines = Files.readAllLines(path, StandardCharsets.UTF_8);
            List<Job> jobs = new ArrayList<>();

            for (String line : lines) {
                String trimmedLine = line.trim();
                if (!trimmedLine.startsWith("|")) {
                    continue;
                }

                // Split line by '|'
                String[] parts = trimmedLine.split("\\|", -1);
                if (parts.length < 6) {
                    continue; // invalid table row
                }

                String jobId = parts[1].trim();
                // Check if this is the header row or the separator row
                if (jobId.equalsIgnoreCase("id") || jobId.startsWith("-")) {
                    continue;
                }

                jobs.add(new Job(jobId, parts[2].trim(), parts[3].trim(), parts[4].trim(), parts[5].trim()));
            }
            return jobs;
        } catch (IOException e) {
            throw new RuntimeException("Error reading job database: " + e.getMessage() + ". The database file may be corrupted or missing. Please check if the data/jobs.md file exists and has the correct format.", e);
        }
    }

    private void writeJobs(List<Job> jobs) {
        Path path = Paths.get(filePath);
        try {
            // Ensure parent directory exists
            Path parentDir = path.getParent();
            if (parentDir != null && !Files.exists(parentDir)) {
                Files.createDirectories(parentDir);
            }

            StringBuilder sb = new StringBuilder();
            sb.append("# Galaxium Travels HR Database\n\n## Jobs\n\n");
            sb.append("| id | job_title | description | required_skills | salary_range |\n");
            sb.append("|---|---|---|---|---|\n");
            for (Job job : jobs) {
                sb.append(String.format("|%s|%s|%s|%s|%s|\n",
                        job.id, job.jobTitle, job.description, job.requiredSkills, job.salaryRange));
            }

            Files.writeString(path, sb.toString(), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new RuntimeException("Error writing to job database: " + e.getMessage() + ". The system may not have write permissions to the data directory, or the data/jobs.md file may be locked by another process.", e);
        }
    }
}
