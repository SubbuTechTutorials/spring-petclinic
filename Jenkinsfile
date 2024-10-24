pipeline {
    agent any

    tools {
        jdk 'JDK 17'
        maven 'maven 3.9.8'
    }

    environment {
        GIT_REPO = 'https://github.com/SubbuTechTutorials/spring-petclinic.git'
        GIT_BRANCH = 'qa'
        GIT_CREDENTIALS_ID = 'github-credentials'
        TRIVY_PAT_CREDENTIALS_ID = 'github-pat'

        AWS_ACCOUNT_ID = '905418425077'
        ECR_REPO_URL = '905418425077.dkr.ecr.ap-south-1.amazonaws.com/qa-petclinic'
        AWS_REGION_ECR = 'ap-south-1'

        SONARQUBE_HOST_URL = credentials('sonarqube-host-url')
        SONARQUBE_PROJECT_KEY = 'PetClinic'
        SONARQUBE_TOKEN = credentials('sonar-credentials')

        TRIVY_DB_CACHE = "/var/lib/jenkins/trivy-db"

        EKS_CLUSTER_NAME = 'devops-petclinicapp-dev-ap-south-1'
        AWS_REGION_EKS = 'ap-south-1'

        SLACK_CHANNEL = '#project-petclinic'
    }

    options {
        skipStagesAfterUnstable()
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: "${GIT_BRANCH}", url: "${GIT_REPO}", credentialsId: "${GIT_CREDENTIALS_ID}"
                sh 'pwd'  
                sh 'ls -l'  
                stash name: 'source-code', includes: '**/*'
            }
        }
     stage('Trivy Scan Repository') {
                    steps {
                        script {
                            if (!fileExists('trivy-scan-success')) {
                                sh "mkdir -p ${TRIVY_DB_CACHE}"

                                withCredentials([string(credentialsId: TRIVY_PAT_CREDENTIALS_ID, variable: 'GITHUB_TOKEN')]) {
                                    def dbAge = sh(script: "find ${TRIVY_DB_CACHE} -name 'db.lock' -mtime +7 | wc -l", returnStdout: true).trim()
                                    if (dbAge == '0') {
                                        sh '''
                                        trivy fs --cache-dir ${TRIVY_DB_CACHE} \
                                            --exit-code 1 --severity HIGH,CRITICAL \
                                            --token $GITHUB_TOKEN . > trivy-scan-report.txt
                                        '''
                                    } else {
                                        sh '''
                                        trivy fs --cache-dir ${TRIVY_DB_CACHE} \
                                            --skip-db-update --exit-code 1 \
                                            --severity HIGH,CRITICAL . > trivy-scan-report.txt
                                        '''
                                    }
                                }

                                writeFile file: 'trivy-scan-success', text: ''
                            }
                        }
                    }
                }
    
        stage('Run Unit Tests with JaCoCo') {
            steps {
                sh 'mvn clean test jacoco:prepare-agent'
            }
        }

        stage('Run Integration Tests with JaCoCo') {
            steps {
                sh 'chmod +x ./scripts/run-integration-tests.sh'
                sh './scripts/run-integration-tests.sh jacoco:prepare-agent'
            }
        }

        stage('SonarQube Analysis') {
            steps {
                script {
                    if (!fileExists('sonarqube-analysis-success')) {
                        withSonarQubeEnv('SonarQube') {
                            sh '''
                            mvn clean verify sonar:sonar \
                                -Dsonar.projectKey=${SONARQUBE_PROJECT_KEY} \
                                -Dsonar.host.url=$SONARQUBE_HOST_URL \
                                -Dsonar.login=$SONARQUBE_TOKEN
                            '''
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
                        def COMMIT_HASH = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                        def IMAGE_TAG = "${COMMIT_HASH}-${BUILD_NUMBER}"
                        env.DOCKER_IMAGE = "${ECR_REPO_URL}:${IMAGE_TAG}"

                        if (!env.DOCKER_IMAGE) {
                            error "Failed to set DOCKER_IMAGE."
                        }
                        echo "DOCKER_IMAGE: ${env.DOCKER_IMAGE}"

                        sh 'docker build -t $DOCKER_IMAGE . --progress=plain'
                        writeFile file: 'docker-build-success', text: ''
                    }
                }
            }
        }

stage('Functional Testing of Docker Image with MySQL') {
    steps {
        script {
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                // Update kubeconfig to ensure kubectl can access the cluster
                sh """
                aws configure set region ${AWS_REGION_EKS}
                aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                """

                // Fetch the MySQL credentials from Kubernetes Secret in the QA namespace
                def MYSQL_USER = sh(script: "kubectl get secret db-secrets-qa -n qa -o jsonpath='{.data.MYSQL_USER}' | base64 --decode", returnStdout: true).trim()
                def MYSQL_PASSWORD = sh(script: "kubectl get secret db-secrets-qa -n qa -o jsonpath='{.data.MYSQL_PASSWORD}' | base64 --decode", returnStdout: true).trim()
                def MYSQL_ROOT_PASSWORD = sh(script: "kubectl get secret db-secrets-qa -n qa -o jsonpath='{.data.MYSQL_ROOT_PASSWORD}' | base64 --decode", returnStdout: true).trim()

                // Fetch the MySQL URL and Database from the ConfigMap
                def MYSQL_DATABASE = sh(script: "kubectl get cm app-config-qa -n qa -o jsonpath='{.data.MYSQL_DATABASE}'", returnStdout: true).trim()

                def mysqlContainerName = "mysql-test"
                def petclinicContainerName = "petclinic-test"
                def petclinicImage = "${env.DOCKER_IMAGE}"

                if (!petclinicImage) {
                    error("Docker image for PetClinic is not set. Please verify the image configuration.")
                }

                try {
                    // Start the MySQL container
                    sh """
                    docker run -d --name ${mysqlContainerName} \
                        -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
                        -e MYSQL_DATABASE=${MYSQL_DATABASE} \
                        -e MYSQL_USER=${MYSQL_USER} \
                        -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
                        mysql:8.4
                    """

                    // Wait for MySQL to become ready
                    def isMysqlReady = false
                    for (int i = 0; i < 10; i++) {
                        echo "Waiting for MySQL to be ready (Attempt ${i + 1}/10)..."
                        def mysqlStatus = sh(script: "docker exec ${mysqlContainerName} mysqladmin ping -u root -p${MYSQL_ROOT_PASSWORD}", returnStatus: true)
                        if (mysqlStatus == 0) {
                            isMysqlReady = true
                            echo "MySQL is ready."
                            break
                        }
                        sleep 10
                    }

                    if (!isMysqlReady) {
                        error('MySQL container did not become ready.')
                    }

                    // Start the PetClinic container linked with MySQL (updating the MYSQL_URL to use internal Docker network)
                    sh """
                    docker run -d --name ${petclinicContainerName} \
                        --link ${mysqlContainerName}:mysql \
                        -e MYSQL_URL=jdbc:mysql://mysql:3306/${MYSQL_DATABASE} \
                        -e MYSQL_USER=${MYSQL_USER} \
                        -e MYSQL_PASSWORD=${MYSQL_PASSWORD} \
                        -e MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD} \
                        -p 8082:8081 ${petclinicImage}
                    """

                    // Check the health of the PetClinic application
                    def petclinicHealth = false
                    for (int i = 0; i < 10; i++) {
                        echo "Checking PetClinic health (Attempt ${i + 1}/10)..."
                        def healthStatus = sh(script: "curl -s http://localhost:8082/actuator/health | grep UP", returnStatus: true)
                        if (healthStatus == 0) {
                            petclinicHealth = true
                            echo "PetClinic is healthy."
                            break
                        }
                        sleep 10
                    }

                    if (!petclinicHealth) {
                        sh "docker logs ${petclinicContainerName}"
                        error('PetClinic application did not become healthy.')
                    }

                    echo "PetClinic and MySQL containers are running and healthy."
                } finally {
                    // Clean up the containers after the test
                    sh "docker stop ${mysqlContainerName} ${petclinicContainerName} || true"
                    sh "docker rm ${mysqlContainerName} ${petclinicContainerName} || true"
                }
            }
        }
    }
}

        stage('Scan Docker Image with Trivy') {
            steps {
               sh """
                trivy image --cache-dir ${TRIVY_DB_CACHE} --skip-db-update ${env.DOCKER_IMAGE} > docker-scan-report.txt
              """
            }
        }
      
        stage('Send Reports via Email') {
    steps {
        script {
            // Check if both the Trivy scan report and Docker image scan report exist
            if (fileExists('trivy-scan-report.txt') && fileExists('docker-scan-report.txt')) {
                emailext(
                    to: 'nagaraju.kjkc@gmail.com, ssrmca07@gmail.com, kandlaguntaniranjanreddy1231@gmail.com',
                    subject: "QA Reports: Trivy Scan Report & Docker Image Scan Report",
                    body: """
                        Hello,

                        Please find attached the Trivy scan report and Docker image scan report for the QA branch.

                        Best regards,
                        Jenkins Team
                    """,
                    attachLog: true,  // Attach console log (optional)
                    attachmentsPattern: "trivy-scan-report.txt, docker-scan-report.txt"
                )
                echo "Scan reports (Trivy and Docker Image) have been sent to: nagaraju.kjkc@gmail.com, ssrmca07@gmail.com, kandlaguntaniranjanreddy1231@gmail.com."
            } else {
                echo "Report files not found! Skipping email notification."
            }
        }
    }
}


        stage('Push Docker Image to AWS ECR') {
            steps {
                script {
                    if (!fileExists('docker-push-success')) {
                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                            sh """
                            aws ecr get-login-password --region ${AWS_REGION_ECR} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION_ECR}.amazonaws.com
                            docker push ${env.DOCKER_IMAGE}
                            """
                        }
                        writeFile file: 'docker-push-success', text: ''
                    }
                }
            }
        }

    

    stage('Update Kubernetes Deployment') {
        steps {
            script {
                // Unstash the checked-out code before running the sed command
                unstash 'source-code'
            
                 // Check if the 'k8s' directory exists and list files to confirm the path
                sh 'ls -l k8s/'
            
                // Update the image in the petclinic-deployment.yaml file
                sh "sed -i 's|image: .*|image: ${env.DOCKER_IMAGE}|' k8s/petclinic-deployment.yaml"
            }
        }
    }




        stage('Manual Approval') {
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        mail(
                            to: 'ssrmca07@gmail.com',
                            subject: "Manual Approval Needed for ${env.JOB_NAME}",
                            body: "Go to build URL and approve the deployment: ${env.BUILD_URL}"
                        )
                        input message: 'Do you want to deploy the application?', submitter: 'approver'
                    }
                }
            }
        }

        stage('Deploy MySQL to EKS') {
            steps {
                script {
                    def mysqlDeploymentExists = sh(script: "kubectl get deployment -n qa mysql-db", returnStatus: true) == 0

                    if (!mysqlDeploymentExists) {
                        unstash 'source-code'
                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                            sh """
                            aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                            sed -i 's/namespace: dev/namespace: qa/g' k8s/mysql-service.yaml
                            sed -i 's/namespace: dev/namespace: qa/g' k8s/mysql-deployment.yaml
                            kubectl apply -f k8s/mysql-service.yaml -n qa
                            kubectl apply -f k8s/mysql-deployment.yaml -n qa
                            """
                        }
                    } else {
                        echo "MySQL Deployment already exists."
                    }
                }
            }
        }

stage('Check MySQL Readiness') {
    steps {
        script {
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                // Update kubeconfig
                sh "aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}"
                
                def maxRetries = 10
                def retryInterval = 30
                def allPodsReady = false

                for (int i = 0; i < maxRetries; i++) {
                    echo "Checking MySQL pods readiness (Attempt ${i + 1}/${maxRetries})..."
                    
                    // Get the status of all pods with label 'app=mysql'
                    def podStatuses = sh(script: """
                        kubectl get pod -n qa -l app=mysql -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase}{"\\n"}{end}'
                    """, returnStdout: true).trim()

                    echo "MySQL Pod statuses:\n${podStatuses}"

                    // Check if all MySQL pods are in 'Running' state
                    def runningPods = sh(script: """
                        kubectl get pod -n qa -l app=mysql -o jsonpath='{.items[*].status.phase}' | grep -o 'Running' | wc -l
                    """, returnStdout: true).trim()

                    def totalPods = sh(script: """
                        kubectl get pod -n qa -l app=mysql --no-headers | wc -l
                    """, returnStdout: true).trim()

                    if (runningPods.toInteger() == totalPods.toInteger()) {
                        allPodsReady = true
                        echo "All MySQL pods are healthy and running."
                        break
                    } else {
                        echo "Not all MySQL pods are running yet. Retrying in ${retryInterval} seconds..."
                    }

                    sleep retryInterval
                }

                if (!allPodsReady) {
                    error('MySQL service did not become healthy.')
                }
            }
        }
    }
}

        
 stage('Deploy PetClinic to EKS') {
    steps {
        unstash 'source-code'
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
            script {
                sh """
                aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}

                # Update namespace from 'dev' to 'qa' and apply the deployment YAML
                sed -i 's/namespace: dev/namespace: qa/g' k8s/petclinic-deployment.yaml
                sed -i 's/namespace: dev/namespace: qa/g' k8s/petclinic-service.yaml
                
                # Apply the updated deployment file
                kubectl apply -f k8s/petclinic-deployment.yaml -n qa
                kubectl apply -f k8s/petclinic-service.yaml -n qa
                """
            }
        }
    }
}

stage('Check PetClinic Health') {
    steps {
        script {
            withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                def maxRetries = 10
                def retryInterval = 30
                def allPodsReady = false

                for (int i = 0; i < maxRetries; i++) {
                    echo "Checking PetClinic health (Attempt ${i + 1}/${maxRetries})..."
                    
                    // Get the status of all pods with label 'app=petclinic'
                    def podStatuses = sh(script: """
                        kubectl get pod -n qa -l app=petclinic -o jsonpath='{range .items[*]}{.metadata.name}: {.status.phase}{"\\n"}{end}'
                    """, returnStdout: true).trim()

                    echo "Pod statuses:\n${podStatuses}"

                    // Check if all pods are in 'Running' state
                    def runningPods = sh(script: """
                        kubectl get pod -n qa -l app=petclinic -o jsonpath='{.items[*].status.phase}' | grep -o 'Running' | wc -l
                    """, returnStdout: true).trim()

                    def totalPods = sh(script: """
                        kubectl get pod -n qa -l app=petclinic --no-headers | wc -l
                    """, returnStdout: true).trim()

                    if (runningPods.toInteger() == totalPods.toInteger()) {
                        allPodsReady = true
                        echo "All PetClinic pods are healthy and running."
                        break
                    } else {
                        echo "Not all PetClinic pods are running yet. Retrying in ${retryInterval} seconds..."
                    }

                    sleep retryInterval
                }

                if (!allPodsReady) {
                    error('PetClinic application did not become healthy.')
                }
            }
        }
    }
}

stage('Smoke Tests') {
    steps {
        script {
            // Fetch the Load Balancer DNS from the Kubernetes service in the 'qa' namespace
            def loadBalancerDNS = sh(script: """
                kubectl get svc petclinic-service-qa -n qa -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
            """, returnStdout: true).trim()

            if (loadBalancerDNS == "") {
                error "Load Balancer DNS not found. Please check the petclinic-service-qa service in the qa namespace."
            }

            echo "Updating PUBLIC_IP_OR_DOMAIN in run-smoke-tests.sh with Load Balancer DNS: ${loadBalancerDNS}"

            // Update the PUBLIC_IP_OR_DOMAIN in the run-smoke-tests.sh script
            sh """
            sed -i 's|PUBLIC_IP_OR_DOMAIN=.*|PUBLIC_IP_OR_DOMAIN="${loadBalancerDNS}"|' ./scripts/run-smoke-tests.sh
            """

            // Set execute permission and run the smoke test script
            sh 'chmod +x ./scripts/run-smoke-tests.sh'
            sh './scripts/run-smoke-tests.sh'
        }
    }
}


        stage('Regression Tests') {
            steps {
                sh 'chmod +x ./scripts/run-regression-tests.sh'
                sh './scripts/run-regression-tests.sh'
            }
        }
    }

    post {
    always {
        cleanWs()
    }
    success {
        slackSend(channel: '#project-petclinic', color: 'good', message: """
        SUCCESS: Job '${env.JOB_NAME}' build #${currentBuild.number} succeeded.
        Scan reports have been emailed to: nagaraju.kjkc@gmail.com, ssrmca07@gmail.com, kandlaguntaniranjanreddy1231@gmail.com.
        """)
    }
    failure {
        slackSend(channel: '#project-petclinic', color: 'danger', message: """
        FAILURE: Job '${env.JOB_NAME}' build #${currentBuild.number} failed.
        No scan reports were sent.
        """)
    }
    unstable {
        slackSend(channel: '#project-petclinic', color: 'warning', message: """
        UNSTABLE: Job '${env.JOB_NAME}' build #${currentBuild.number} is unstable.
        Check the logs for further investigation.
        """)
    }
  }
}
