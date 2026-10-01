

# Stage 1: Build the application
FROM maven:3.8-eclipse-temurin-11 AS build

WORKDIR /app

COPY pom.xml mvnw ./
COPY .mvn .mvn
COPY src ./src

RUN chmod +x mvnw \
    && unset MAVEN_CONFIG MAVEN_ARGS \
    && ./mvnw -B -Dmaven.repo.local=/tmp/m2 clean package -DskipTests

# Stage 2: Run the application
FROM eclipse-temurin:11-jre

WORKDIR /app

COPY --from=build /app/target/*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]
