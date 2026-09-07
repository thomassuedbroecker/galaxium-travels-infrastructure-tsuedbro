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

# Install wget for the Docker healthcheck (not present in the base JRE image)
RUN apt-get update -qq && apt-get install -y --no-install-recommends wget && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Quarkus fast-jar layout: quarkus-run.jar + lib/ + app/ + quarkus/
COPY --from=builder /build/target/quarkus-app/ ./

# Seed data — used as fallback when no host volume is mounted.
# When docker-compose mounts ../hr_database_backend_java/data:/app/data,
# the volume takes precedence and this baked-in file is not used.
RUN mkdir -p data
COPY data/employees.md data/employees.md

EXPOSE 8089

LABEL org.opencontainers.image.title="hr-database-backend-java" \
      org.opencontainers.image.description="Galaxium Travels HR Database Java Backend (Quarkus)" \
      org.opencontainers.image.version="1.0.0"

CMD ["java", "-jar", "quarkus-run.jar"]
