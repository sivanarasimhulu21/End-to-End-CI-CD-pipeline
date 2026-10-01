
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
        timeout(time: 45, unit: 'MINUTES')
    }

    parameters {
        string(
            name: 'DOCKERHUB_REPO',
            defaultValue: 'shimbu374/student-management-system-app',
            description: 'Docker Hub repository: username/image'
        )
        booleanParam(
            name: 'SONAR_ENABLED',
            defaultValue: false,
            description: 'Enable only after SonarQube is configured'
        )
        string(
            name: 'STAGING_HOST',
            defaultValue: '',
            description: 'Staging EC2 IP or DNS; leave blank to skip deployment'
        )
        string(
            name: 'STAGING_USER',
            defaultValue: 'ubuntu',
            description: 'SSH username for staging EC2'
        )
    }

    environment {
        TEST_DB_NAME = 'student_management'
        TEST_DB_USER = 'student'
        TEST_DB_PASSWORD = 'student_test_pw'
        TEST_DB_ROOT_PASSWORD = 'ci_root_pw'
        TEST_NETWORK = 'student-ci-net'
        APP_CONTAINER = 'student-management-system-app'
    }

    stages {
        stage('01 - Checkout Source') {
            steps {
                checkout scm
                sh 'git log -1 --oneline'
            }
        }

        stage('02 - Validate Project') {
            steps {
                sh '''
                    set -eu
                    test -f pom.xml || {
                        echo "ERROR: pom.xml is missing"
                        exit 1
                    }
                    test -d src || {
                        echo "ERROR: src directory is missing"
                        exit 1
                    }
                    test -f Dockerfile || {
                        echo "ERROR: Dockerfile is missing"
                        exit 1
                    }
                    echo "Project structure validated."
                    echo "Maven wrapper is not required by this pipeline."
                '''
            }
        }

        stage('03 - Start Test Database') {
            steps {
                sh '''
                    set -eu
                    docker rm -f student-test-db 2>/dev/null || true
                    docker network create "$TEST_NETWORK" 2>/dev/null || true

                    docker run -d \
                      --name student-test-db \
                      --network "$TEST_NETWORK" \
                      --network-alias student-test-db \
                      -e MYSQL_ROOT_PASSWORD="$TEST_DB_ROOT_PASSWORD" \
                      -e MYSQL_DATABASE="$TEST_DB_NAME" \
                      -e MYSQL_USER="$TEST_DB_USER" \
                      -e MYSQL_PASSWORD="$TEST_DB_PASSWORD" \
                      --health-cmd='mysqladmin ping -h 127.0.0.1 -uroot -pci_root_pw --silent' \
                      --health-interval=5s \
                      --health-timeout=3s \
                      --health-retries=30 \
                      mysql:8.0

                    for i in $(seq 1 60); do
                      STATUS=$(docker inspect \
                        -f '{{.State.Health.Status}}' student-test-db)
                      if [ "$STATUS" = "healthy" ]; then
                        echo "Test database is ready."
                        exit 0
                      fi
                      sleep 2
                    done

                    docker logs student-test-db
                    echo "ERROR: Test database did not become healthy."
                    exit 1
                '''
            }
        }

        stage('04 - Compile Application') {
            steps {
                sh '''
                    set -eu
                    mkdir -p "$WORKSPACE/.m2"

                    docker run --rm \
                      --user "$(id -u):$(id -g)" \
                      --network "$TEST_NETWORK" \
                      -v "$WORKSPACE:/workspace" \
                      -w /workspace \
                      maven:3.9-eclipse-temurin-21 \
                      mvn -B \
                        -Dmaven.repo.local=/workspace/.m2/repository \
                        -DskipTests compile
                '''
            }
        }

        stage('05 - Automated Tests') {
            steps {
                sh '''
                    set -eu
                    docker run --rm \
                      --user "$(id -u):$(id -g)" \
                      --network "$TEST_NETWORK" \
                      -v "$WORKSPACE:/workspace" \
                      -w /workspace \
                      -e SPRING_DATASOURCE_URL="jdbc:mysql://student-test-db:3306/${TEST_DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC" \
                      -e SPRING_DATASOURCE_USERNAME="$TEST_DB_USER" \
                      -e SPRING_DATASOURCE_PASSWORD="$TEST_DB_PASSWORD" \
                      maven:3.9-eclipse-temurin-21 \
                      mvn -B \
                        -Dmaven.repo.local=/workspace/.m2/repository \
                        test
                '''
            }
        }

        stage('06 - Package Application') {
            steps {
                sh '''
                    set -eu
                    docker run --rm \
                      --user "$(id -u):$(id -g)" \
                      --network "$TEST_NETWORK" \
                      -v "$WORKSPACE:/workspace" \
                      -w /workspace \
                      -e SPRING_DATASOURCE_URL="jdbc:mysql://student-test-db:3306/${TEST_DB_NAME}?useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC" \
                      -e SPRING_DATASOURCE_USERNAME="$TEST_DB_USER" \
                      -e SPRING_DATASOURCE_PASSWORD="$TEST_DB_PASSWORD" \
                      maven:3.9-eclipse-temurin-21 \
                      mvn -B \
                        -Dmaven.repo.local=/workspace/.m2/repository \
                        -DskipTests package

                    ls -lh target/*.jar
                '''
            }
        }

        stage('07 - SonarQube Analysis') {
            when {
                expression { params.SONAR_ENABLED }
            }
            steps {
                withCredentials([
                    string(
                        credentialsId: 'sonarqube-token',
                        variable: 'SONAR_TOKEN'
                    )
                ]) {
                    sh '''
                        set -eu
                        test -n "$SONAR_HOST_URL" || {
                          echo "Configure SONAR_HOST_URL before enabling SonarQube."
                          exit 1
                        }

                        docker run --rm \
                          --user "$(id -u):$(id -g)" \
                          -v "$WORKSPACE:/workspace" \
                          -w /workspace \
                          -e SONAR_HOST_URL \
                          -e SONAR_TOKEN \
                          maven:3.9-eclipse-temurin-21 \
                          mvn -B \
                            -Dmaven.repo.local=/workspace/.m2/repository \
                            org.sonarsource.scanner.maven:sonar-maven-plugin:3.11.0.3922:sonar \
                            -Dsonar.host.url="$SONAR_HOST_URL" \
                            -Dsonar.token="$SONAR_TOKEN"
                    '''
                }
            }
        }

        stage('08 - Filesystem Security Scan') {
            steps {
                sh '''
                    docker run --rm \
                      -v "$WORKSPACE:/src" \
                      aquasec/trivy:latest \
                      fs --scanners vuln,misconfig,secret \
                      --severity HIGH,CRITICAL \
                      --exit-code 1 /src
                '''
            }
        }

        stage('09 - Build Docker Image') {
            steps {
                sh '''
                    set -eu
                    docker build --pull \
                      -t "$DOCKERHUB_REPO:$BUILD_NUMBER" \
                      -t "$DOCKERHUB_REPO:latest" .
                '''
            }
        }

        stage('10 - Docker Image Security Scan') {
            steps {
                sh '''
                    docker run --rm \
                      -v /var/run/docker.sock:/var/run/docker.sock \
                      aquasec/trivy:latest \
                      image --scanners vuln \
                      --severity HIGH,CRITICAL \
                      --exit-code 1 \
                      "$DOCKERHUB_REPO:$BUILD_NUMBER"
                '''
            }
        }

        stage('11 - Push Image to Docker Hub') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )
                ]) {
                    sh '''
                        set -eu
                        set +x
                        printf '%s' "$DH_TOKEN" |
                          docker login -u "$DH_USER" --password-stdin

                        docker push "$DOCKERHUB_REPO:$BUILD_NUMBER"
                        docker push "$DOCKERHUB_REPO:latest"
                        docker logout
                    '''
                }
            }
        }

        stage('12 - Deploy and Smoke Test') {
            when {
                expression {
                    return params.STAGING_HOST?.trim()
                }
            }
            steps {
                sshagent(credentials: ['staging-ssh-key']) {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-creds',
                            usernameVariable: 'DH_USER',
                            passwordVariable: 'DH_TOKEN'
                        )
                    ]) {
                        sh '''
                            set -eu
                            set +x

                            REMOTE="$STAGING_USER@$STAGING_HOST"
                            IMAGE="$DOCKERHUB_REPO:$BUILD_NUMBER"

                            printf '%s' "$DH_TOKEN" |
                              ssh -o StrictHostKeyChecking=accept-new "$REMOTE" \
                              "docker login -u '$DH_USER' --password-stdin &&
                               docker pull '$IMAGE' &&
                               (docker rm -f '$APP_CONTAINER' || true) &&
                               docker run -d \
                                 --name '$APP_CONTAINER' \
                                 --restart unless-stopped \
                                 --env-file /opt/student-management/.env \
                                 -p 8080:8080 '$IMAGE'"

                            ssh -o StrictHostKeyChecking=accept-new "$REMOTE" '
                              for i in $(seq 1 30); do
                                CODE=$(curl -sS -o /dev/null -w "%{http_code}" \
                                  http://127.0.0.1:8080/ || true)
                                if [ "$CODE" != "000" ] &&
                                   [ "${CODE:-000}" -lt 500 ]; then
                                  echo "HTTP smoke test responded: $CODE"
                                  exit 0
                                fi
                                sleep 5
                              done
                              docker logs student-management-system-app
                              exit 1
                            '
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh '''
                docker rm -f student-test-db 2>/dev/null || true
                docker network rm "$TEST_NETWORK" 2>/dev/null || true
            '''
            echo 'Pipeline finished. Review the stage results above.'
        }
    }
}
