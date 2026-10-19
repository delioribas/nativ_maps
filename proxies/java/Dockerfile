# Compila con Maven y arranca con solo el JRE.
#   docker build -t nativ-maps-proxy .
#   docker run -p 8080:8080 -e PROXY_TOKEN -e AWS_REGION -e ALS_API_KEY nativ-maps-proxy

FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
COPY pom.xml .
COPY src ./src
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:17-jre
COPY --from=build /src/target/nativ-maps-proxy.jar /app/nativ-maps-proxy.jar
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/nativ-maps-proxy.jar"]
