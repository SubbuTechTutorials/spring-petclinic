# Use a Maven image with JDK 17 for the build stage
FROM maven:3.9.4-eclipse-temurin-17-alpine AS build

WORKDIR /app

# Copy the pom.xml first and download the dependencies
COPY pom.xml ./
RUN mvn dependency:go-offline -B

# Copy the source code after dependencies are cached
COPY src ./src

# Package the application
RUN mvn clean package -DskipTests -Ddockerfile.skip=true

# Use JDK 17 for the runtime stage
FROM eclipse-temurin:17-jdk-alpine AS runtime

WORKDIR /app

# Copy the built JAR from the build stage
COPY --from=build /app/target/spring-petclinic-*.jar /app/app.jar

# Define the entry point
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
