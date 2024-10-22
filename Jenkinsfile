pipeline {
    agent any

    tools {
        jdk 'JDK 17'  // Name that matches your Jenkins configuration
        maven 'maven 3.9.8'  // Make sure this matches the Maven name configured in Global Tool Configuration
    }

    environment {
        GIT_REPO = 'https://github.com/SubbuTechTutorials/spring-petclinic.git'
        GIT_BRANCH = 'feature'
        GIT_CREDENTIALS_ID = 'github-credentials'
        TRIVY_PAT_CREDENTIALS_ID = 'github-pat'
        
        // SonarQube settings
        SONARQUBE_HOST_URL = 'http://44.201.120.105:9000/'  // Replace with your SonarQube URL
        SONARQUBE_PROJECT_KEY = 'PetClinic'
        SONARQUBE_TOKEN = credentials('sonar-credentials')
        
        // AWS ECR settings
        AWS_ACCOUNT_ID = '905418425077'  // Replace with your AWS Account ID
        ECR_REPO_URL = "${AWS_ACCOUNT_ID}.dkr.ecr.ap-south-1.amazonaws.com/dev/petclinic"
        AWS_REGION_ECR = 'ap-south-1'  // ECR region
        
        // EKS Cluster name and region
        EKS_CLUSTER_NAME = 'devops-petclinicapp-dev-ap-south-1'
        AWS_REGION_EKS = 'ap-south-1'  // EKS region
        
        // Set local directory to cache Trivy DB
        TRIVY_DB_CACHE = "/var/lib/jenkins/trivy-db"
    }

    options {
        // Skip stages after unstable or failure
        skipStagesAfterUnstable()
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: "${GIT_BRANCH}", url: "${GIT_REPO}", credentialsId: "${GIT_CREDENTIALS_ID}"
                stash name: 'source-code', includes: '**/*'
            }
        }

        stage('Trivy Scan Repository') {
            steps {
                script {
                    if (!fileExists('trivy-scan-success')) {
                        sh "mkdir -p ${TRIVY_DB_CACHE}"
                        withCredentials([string(credentialsId: "${TRIVY_PAT_CREDENTIALS_ID}", variable: 'GITHUB_TOKEN')]) {
                            sh 'export TRIVY_AUTH_TOKEN=$GITHUB_TOKEN'
                            def dbExists = sh(script: "test -f ${TRIVY_DB_CACHE}/db.lock && echo 'true' || echo 'false'", returnStdout: true).trim()
                            if (dbExists == 'true') {
                                sh "trivy fs --cache-dir ${TRIVY_DB_CACHE} --skip-db-update --exit-code 1 --severity HIGH,CRITICAL ."
                            } else {
                                sh "trivy fs --cache-dir ${TRIVY_DB_CACHE} --exit-code 1 --severity HIGH,CRITICAL ."
                            }
                        }
                        writeFile file: 'trivy-scan-success', text: ''
                    }
                }
            }
        }

        stage('Run Unit Tests') {
            steps {
                script {
                    if (!fileExists('unit-tests-success')) {
                        sh 'mvn test -DskipTests=false'
                        writeFile file: 'unit-tests-success', text: ''
                    }
                }
            }
        }

        stage('Generate JaCoCo Coverage Report') {
            steps {
                script {
                    if (!fileExists('jacoco-report-success')) {
                        sh 'mvn jacoco:report'
                        writeFile file: 'jacoco-report-success', text: ''
                    }
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    if (!fileExists('sonarqube-analysis-success')) {
                        withSonarQubeEnv('SonarQube') {
                            sh """
                            mvn clean verify sonar:sonar \
                            -Dsonar.projectKey=${SONARQUBE_PROJECT_KEY} \
                            -Dsonar.host.url=${SONARQUBE_HOST_URL} \
                            -Dsonar.login=${SONARQUBE_TOKEN}
                            """
                        }
                        writeFile file: 'sonarqube-analysis-success', text: ''
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    if (!fileExists('docker-build-success')) {
                        // Get the short Git commit hash and define DOCKER_IMAGE here
                        def COMMIT_HASH = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                        def IMAGE_TAG = "${COMMIT_HASH}-${env.BUILD_NUMBER}"
                        env.DOCKER_IMAGE = "${ECR_REPO_URL}:${IMAGE_TAG}"  // Defined DOCKER_IMAGE here

                        // Build the Docker image and tag it with Git commit hash and build number
                        sh "docker build -t ${env.DOCKER_IMAGE} . --progress=plain"
                        writeFile file: 'docker-build-success', text: ''
                    }
                }
            }
        }
        stage('Test Docker Image with MySQL') {
    steps {
        script {
            def mysqlContainerName = "mysql-test"
            def petclinicContainerName = "petclinic-test"
            def petclinicImage = "${env.DOCKER_IMAGE}"

            try {
                // Start MySQL container with version 8.4
                sh """
                docker run -d --name ${mysqlContainerName} \
                -e MYSQL_ROOT_PASSWORD=root \
                -e MYSQL_DATABASE=petclinic \
                -e MYSQL_USER=petclinic \
                -e MYSQL_PASSWORD=petclinic \
                mysql:8.4
                """

                // Wait for MySQL to be ready (simple loop to wait for a healthy state)
                def maxRetries = 10
                def retryInterval = 10
                def isMysqlReady = false

                for (int i = 0; i < maxRetries; i++) {
                    echo "Waiting for MySQL to be ready (Attempt ${i + 1}/${maxRetries})..."
                    def mysqlStatus = sh(script: "docker exec ${mysqlContainerName} mysqladmin ping -u root -proot", returnStatus: true)
                    if (mysqlStatus == 0) {
                        isMysqlReady = true
                        echo "MySQL is ready."
                        break
                    }
                    sleep retryInterval
                }

                if (!isMysqlReady) {
                    error('MySQL container did not become ready.')
                }

                // Run PetClinic container with MySQL as the backend
                sh """
                docker run -d --name ${petclinicContainerName} \
                --link ${mysqlContainerName}:mysql \
                -e MYSQL_URL=jdbc:mysql://mysql:3306/petclinic \
                -e MYSQL_USER=petclinic \
                -e MYSQL_PASSWORD=petclinic \
                -e MYSQL_ROOT_PASSWORD=root \
                -p 8082:8081 ${petclinicImage}
                """

                // Wait for PetClinic to be ready (Check the health endpoint on port 8082)
                def petclinicHealth = false
                for (int i = 0; i < maxRetries; i++) {
                    echo "Checking PetClinic health (Attempt ${i + 1}/${maxRetries})..."
                    def healthStatus = sh(script: "curl -s http://localhost:8082/actuator/health | grep UP", returnStatus: true)
                    if (healthStatus == 0) {
                        petclinicHealth = true
                        echo "PetClinic is healthy."
                        break
                    }
                    sleep retryInterval
                }

                if (!petclinicHealth) {
                    echo 'Collecting logs from PetClinic container...'
                    sh "docker logs ${petclinicContainerName}"
                    error('PetClinic application did not become healthy.')
                }

                echo "PetClinic and MySQL containers are running and healthy."
            } finally {
                // Clean up containers (always clean up whether successful or not)
                  sh "docker stop ${mysqlContainerName} ${petclinicContainerName} || true"
                  sh "docker rm ${mysqlContainerName} ${petclinicContainerName} || true"
            }
        }
    }
}


        stage('Scan Docker Image with Trivy') {
            steps {
                script {
                    // Scanning the built Docker image with Trivy using cached DB
                    sh "trivy image --cache-dir ${TRIVY_DB_CACHE} --skip-db-update ${env.DOCKER_IMAGE}"
                }
            }
        }

        stage('Push Docker Image to AWS ECR') {
            steps {
                script {
                    if (!fileExists('docker-push-success')) {
                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                            sh """
                            # Login to AWS ECR
                            aws ecr get-login-password --region ${AWS_REGION_ECR} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION_ECR}.amazonaws.com
                            
                            # Push the Docker image to AWS ECR
                            docker push ${env.DOCKER_IMAGE}
                            """
                        }
                        writeFile file: 'docker-push-success', text: ''  // Mark Docker Push as successful
                    }
                }
            }
        }
    }

    post {
    always {
        cleanWs()  // Clean up the workspace after the build
    }
    success {
        slackSend (channel: '#project-petclinic', color: 'good', message: "SUCCESS: Job '${env.JOB_NAME}' build #${currentBuild.number} succeeded.")
    }
    failure {
        slackSend (channel: '#project-petclinic', color: 'danger', message: "FAILURE: Job '${env.JOB_NAME} build [${currentBuild.number}]' failed.")
    }
    unstable {
        slackSend (channel: '#project-petclinic', color: 'warning', message: "UNSTABLE: Job '${env.JOB_NAME} build [${currentBuild.number}]' is unstable.")
    }
}


}
