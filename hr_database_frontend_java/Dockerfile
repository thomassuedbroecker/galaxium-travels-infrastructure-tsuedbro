# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Build — Maven + Node (via frontend-maven-plugin)
# ─────────────────────────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

COPY pom.xml .
RUN mvn dependency:go-offline -q || true

# Copy full source (Java + webapp)
COPY src/ src/

# Build: frontend-maven-plugin runs npm install + npm run build inside Maven,
# then Maven packages the Quarkus fast-jar containing the React static assets.
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

# HR Database backend URL — overridable at runtime, so one image serves both
# the Java and the Python backend. Each compose file sets it via environment.
ENV HR_BACKEND_URL=http://localhost:8089

EXPOSE 8088

LABEL org.opencontainers.image.title="hr-database-frontend" \
      org.opencontainers.image.description="Galaxium Travels HR Portal (Quarkus + React)" \
      org.opencontainers.image.version="1.0.0"

CMD ["java", "-jar", "quarkus-run.jar"]
