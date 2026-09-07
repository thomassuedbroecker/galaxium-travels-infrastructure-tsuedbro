# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Build — Maven + Node (via frontend-maven-plugin)
# Uses Eclipse Temurin 21 (latest OpenJDK LTS) with Maven pre-installed
# ─────────────────────────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

# Cache dependency resolution separately from the source copy
COPY pom.xml .
RUN mvn dependency:go-offline -q || true

# Copy full source (Java + webapp)
COPY src/ src/

# Build: frontend-maven-plugin runs npm install + npm run build inside Maven
# then Maven packages the Quarkus fat-jar containing the React static assets
RUN mvn package -DskipTests -q

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Runtime — minimal JRE only
# ─────────────────────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy AS runtime

WORKDIR /app

# Quarkus fast-jar layout: quarkus-run.jar + lib/ + app/ + quarkus/
COPY --from=builder /build/target/quarkus-app/ ./

EXPOSE 8088

# HR_API_URL is the Python HR Database backend URL (overridable at runtime)
ENV HR_API_URL=http://localhost:8081

LABEL org.opencontainers.image.title="hr-database-frontend" \
      org.opencontainers.image.description="Galaxium Travels HR Portal (Quarkus + React)" \
      org.opencontainers.image.version="1.0.0"

CMD ["java", "-jar", "quarkus-run.jar"]
