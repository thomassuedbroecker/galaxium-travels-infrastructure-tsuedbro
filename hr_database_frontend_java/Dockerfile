# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Build — Maven + Node (via frontend-maven-plugin)
# ─────────────────────────────────────────────────────────────────────────────
FROM maven:3.9-eclipse-temurin-21 AS builder

WORKDIR /build

COPY pom.xml .
RUN mvn dependency:go-offline -q || true

COPY src/ src/

# Write the backend URL into application.properties before Quarkus augmentation
# so it is recorded into the fast-jar bytecode.  This is the only reliable way
# to set a REST client base URL for Quarkus fast-jar production builds.
# Each compose file passes the correct Docker-network URL via build.args.
ARG HR_BACKEND_URL=http://localhost:8089
RUN printf '\nquarkus.rest-client.hrbackend.url=%s\n' "${HR_BACKEND_URL}" \
    >> src/main/resources/application.properties && \
    mvn package -DskipTests -q

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Runtime — minimal JRE only
# ─────────────────────────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy AS runtime

WORKDIR /app

COPY --from=builder /build/target/quarkus-app/ ./

EXPOSE 8088

LABEL org.opencontainers.image.title="hr-database-frontend" \
      org.opencontainers.image.description="Galaxium Travels HR Portal (Quarkus + React)" \
      org.opencontainers.image.version="1.0.0"

CMD ["java", "-jar", "quarkus-run.jar"]
