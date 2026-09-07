# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Build — Maven
# Uses Eclipse Temurin 21 (OpenJDK LTS) with Maven pre-installed
# ─────────────────────────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

# Cache dependency resolution separately from the source copy
COPY pom.xml .
RUN mvn dependency:go-offline -q || true

# Copy full source
COPY src/ src/

# Build
RUN mvn package -DskipTests -q

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Runtime — minimal JRE only
# ─────────────────────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy AS runtime

WORKDIR /app

# Quarkus fast-jar layout: quarkus-run.jar + lib/ + app/ + quarkus/
COPY --from=builder /build/target/quarkus-app/ ./

# Create data directory and copy initial employees database
RUN mkdir -p data
COPY data/employees.md data/employees.md

EXPOSE 8089

LABEL org.opencontainers.image.title="hr-database-backend-java" \
      org.opencontainers.image.description="Galaxium Travels HR Database Java Backend (Quarkus)" \
      org.opencontainers.image.version="1.0.0"

CMD ["java", "-jar", "quarkus-run.jar"]
