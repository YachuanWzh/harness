# Backend stack: Java

This project's backend is **Java** (Spring ecosystem). Apply these conventions when working here.

## Layout
- `src/main/java/...` application code; `src/test/java/...` mirrors it.
- Layered: `controller` (thin) -> `service` (business logic) -> `repository` (data).

## Testing (TDD — write the failing test first)
- Test framework: **JUnit 5** + **AssertJ**; mock with **Mockito**.
- Run all: `mvn test` (or `./gradlew test`). Single: `mvn -Dtest=FooServiceTest test`.
- Web layer: `@WebMvcTest` + `MockMvc`. Assert on behavior and HTTP contracts.

## Standards
- Constructor injection (no field `@Autowired`). Keep controllers thin.
- Follow standard Java style; format with the project's plugin (Spotless/google-java-format).
- Run the full `mvn test` (or gradle) suite before claiming done.

## Verify commands against the project
The commands above are defaults, not repo facts. Detect the build tool from
`pom.xml` vs `build.gradle(.kts)` and prefer the checked-in wrapper
(`./mvnw`, `./gradlew`) over a locally installed tool.

## Test boundaries & mocking
- Mockito: mock collaborators at service boundaries only; never mock DTOs,
  value objects, or the class under test.
- Web: `@WebMvcTest` + `MockMvc` against the real controller with mocked
  services; keep Jackson serialization real.
- Persistence: `@DataJpaTest` for repository queries; Testcontainers with a
  real database for integration tests — do not mock a repository in its own
  test.

## Key libraries (verify versions against the build file)
- Java 17+; Spring Boot 3.x. JUnit 5 + AssertJ + Mockito 5.x.
- Build: Maven 3.9+ or Gradle 8.x per the repository.
