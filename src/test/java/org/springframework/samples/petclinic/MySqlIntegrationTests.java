package org.springframework.samples.petclinic;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledInNativeImage;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.http.HttpStatus;
import org.springframework.http.RequestEntity;
import org.springframework.http.ResponseEntity;
import org.springframework.samples.petclinic.vet.VetRepository;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.context.aot.DisabledInAotMode;
import org.springframework.web.client.RestTemplate;
import org.testcontainers.containers.MySQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT)
@ActiveProfiles("test")  // Change the profile to "test"
@Testcontainers(disabledWithoutDocker = true)
@DisabledInNativeImage
@DisabledInAotMode
class MySqlIntegrationTests {

    @Container
    static MySQLContainer<?> mysqlContainer = new MySQLContainer<>("mysql:8.0");

    @DynamicPropertySource
    static void overrideProperties(DynamicPropertyRegistry registry) {
        registry.add("spring.datasource.url", mysqlContainer::getJdbcUrl);
        registry.add("spring.datasource.username", mysqlContainer::getUsername);
        registry.add("spring.datasource.password", mysqlContainer::getPassword);
        registry.add("spring.datasource.initialization-mode", () -> "always");  // Ensure schema initialization
    }

    @LocalServerPort
    int port;

    @Autowired
    private VetRepository vets;

    @Autowired
    private RestTemplateBuilder builder;

    @Test
    void testFindAll() throws Exception {
        // Run findAll twice to test caching as well
        vets.findAll();
        vets.findAll(); // served from cache
    }

    @Test
    void testOwnerDetails() {
        RestTemplate template = builder.rootUri("http://localhost:" + port).build();
        ResponseEntity<String> result = template.exchange(RequestEntity.get("/owners/1").build(), String.class);
        assertThat(result.getStatusCode()).isEqualTo(HttpStatus.OK);
    }
}
