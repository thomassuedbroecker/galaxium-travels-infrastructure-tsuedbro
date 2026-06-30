package com.galaxium.hr;

import io.quarkus.runtime.Quarkus;
import io.quarkus.runtime.annotations.QuarkusMain;

/**
 * Quarkus entry point for the HR Database Frontend service.
 * Serves the React SPA as static files and proxies HR API calls
 * to the Python HR Database backend via JAX-RS endpoints.
 */
@QuarkusMain
public class Main {
    public static void main(String... args) {
        Quarkus.run(args);
    }
}
