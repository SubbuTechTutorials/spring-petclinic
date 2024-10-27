pipeline {
    agent any

    tools {
        jdk 'JDK 17'
        maven 'maven 3.9.8'
    }

    environment {
        GIT_REPO = 'https://github.com/SubbuTechTutorials/spring-petclinic.git'
        GIT_BRANCH = 'main'
        GIT_CREDENTIALS_ID = 'github-credentials'
        TRIVY_PAT_CREDENTIALS_ID = 'github-pat'
        TRIVY_DB_CACHE = "/var/lib/jenkins/trivy-db"

        AWS_ACCOUNT_ID = '905418425077'
        ECR_REPO_URL = '905418425077.dkr.ecr.ap-south-1.amazonaws.com/prod-petclinic'
        AWS_REGION_ECR = 'ap-south-1'
        
        AWS_REGION = 'ap-south-1'  // Updated to match your EKS region
        SECRET_NAME = 'prod/petclinic-secrets'
        
        SONARQUBE_HOST_URL = credentials('sonarqube-host-url')
        SONARQUBE_PROJECT_KEY = 'PetClinic'
        SONARQUBE_TOKEN = credentials('sonar-credentials')

        EKS_CLUSTER_NAME = 'devops-petclinicapp-dev-ap-south-1'
        AWS_REGION_EKS = 'ap-south-1'
        
        JMETER_HOME = '/opt/jmeter'
        JMETER_SCRIPT = 'src/test/jmeter/petclinic_test_plan.jmx'
        JMETER_RESULTS = 'jmeter-results/results.jtl'
        JMETER_REPORT = 'jmeter-results/report'

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


        stage('Run Unit Tests') {
            steps {
                sh 'mvn clean test'
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
        
stage('Scan Docker Image with Trivy') {
    steps {
        script {
            // Check if the Trivy DB cache exists
            def trivyDbExists = fileExists("${TRIVY_DB_CACHE}/db.lock")
            if (!trivyDbExists) {
                echo 'Trivy DB does not exist, downloading it once...'
                // Use GitHub PAT to download Trivy DB to avoid rate limits
                withCredentials([string(credentialsId: "${TRIVY_PAT_CREDENTIALS_ID}", variable: 'GITHUB_PAT')]) {
                    sh """
                    export GITHUB_TOKEN=${GITHUB_PAT}
                    trivy --cache-dir ${TRIVY_DB_CACHE} image --download-db-only
                    """
                }
            }

            // Scan Docker image with Trivy using the existing or freshly downloaded DB
            echo 'Scanning Docker image with Trivy...'
            sh """
            trivy --cache-dir ${TRIVY_DB_CACHE} image --skip-db-update ${env.DOCKER_IMAGE} > docker-scan-report.txt
            """
            writeFile file: 'docker-scan-success', text: 'Docker image scan completed successfully'
        }
    }
}


       
stage('Send Reports via Email') {
    steps {
        script {
            if (fileExists('docker-scan-report.txt')) {
                emailext(
                    to: 'ssrmca07@gmail.com',
                    subject: "Prod CICD Reports: Docker Image Scan Report",
                    body: """
                    Hello,

                    Please find attached the Docker image scan report for the QA branch.

                    Best regards,
                    Team DevOps
                    """,
                    attachLog: false,
                    attachmentsPattern: "docker-scan-report.txt"
                )
                echo "Scan reports have been sent."
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
        

        stage('Manual Approval') {
            steps {
                script {
                    timeout(time: 10, unit: 'MINUTES') {
                        def approvalMailContent = """
                        Project: ${env.JOB_NAME}
                        Build Number: ${env.BUILD_NUMBER}
                        Go to build URL and approve the deployment request.
                        URL of build: ${env.BUILD_URL}
                        """
                        mail(
                            to: 'ssrmca07@gmail.com, nagaraju.kjkc@gmail.com',
                            subject: "${currentBuild.result ?: 'IN PROGRESS'} CI: Project name -> PetClinic-Prod", 
                            body: approvalMailContent,
                            mimeType: 'text/plain'
                        )
                        input(
                            id: "DeployGate",
                            message: "Deploy ${params.project_name}?",
                            submitter: "approver",
                            parameters: [choice(name: 'action', choices: ['Deploy'], description: 'Approve deployment')]
                        )
                    }
                }
            }
        }
        
stage('Retrieve MySQL Secrets') {
    steps {
        withCredentials([[
            $class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'aws-eks-credentials'
        ]]) {
            script {
                // Fetch MySQL credentials from AWS Secrets Manager
                def secret = sh(script: "aws secretsmanager get-secret-value --secret-id ${SECRET_NAME} --region ${AWS_REGION} --query SecretString --output text", returnStdout: true).trim()

                // Parse the JSON response to extract the values (requires Pipeline Utility Steps Plugin)
                def secretJson = readJSON text: secret
                env.MYSQL_USER = secretJson.MYSQL_USER
                env.MYSQL_PASSWORD = secretJson.MYSQL_PASSWORD
                env.MYSQL_DATABASE = secretJson.MYSQL_DATABASE
                env.MYSQL_ROOT_PASSWORD = secretJson.MYSQL_ROOT_PASSWORD
               
            }
        }
    }
}

        
 stage('Deploy MySQL to EKS') {
    steps {
        withCredentials([[
            $class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'aws-eks-credentials'
        ]]) {
            script {
                // Check if MySQL deployment exists
                def mysqlDeploymentExists = sh(script: "kubectl get deployment -n prod mysql-db-prod", returnStatus: true) == 0
                if (!mysqlDeploymentExists) {
                    unstash 'source-code'
                    // Configure AWS region and update kubeconfig for EKS
                    sh """
                    aws configure set region ${AWS_REGION_EKS}
                    aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                    kubectl apply -f k8s/mysql-service.yaml -n prod
                    kubectl apply -f k8s/mysql-deployment.yaml -n prod
                    """
                    // Set environment variables after the deployment
                    sh """
                    kubectl set env deployment/mysql-db-prod \
                        MYSQL_USER=${env.MYSQL_USER} \
                        MYSQL_PASSWORD=${env.MYSQL_PASSWORD} \
                        MYSQL_DATABASE=${env.MYSQL_DATABASE} \
                        MYSQL_ROOT_PASSWORD=${env.MYSQL_ROOT_PASSWORD} \
                        -n prod
                    """
                } else {
                    echo "MySQL Deployment already exists."
                }
            }
        }
    }
}


      
        stage('Check MySQL Readiness') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                        sh "aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}"
                        def maxRetries = 10
                        def retryInterval = 30
                        def allPodsReady = false
                        for (int i = 0; i < maxRetries; i++) {
                            echo "Checking MySQL pods readiness (Attempt ${i + 1}/${maxRetries})..."
                            def runningPods = sh(script: "kubectl get pod -n prod -l app=mysql -o jsonpath='{.items[*].status.phase}' | grep -o 'Running' | wc -l", returnStdout: true).trim()
                            def totalPods = sh(script: "kubectl get pod -n prod -l app=mysql --no-headers | wc -l", returnStdout: true).trim()
                            if (runningPods.toInteger() == totalPods.toInteger()) {
                                allPodsReady = true
                                echo "All MySQL pods are healthy and running."
                                break
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
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
            script {
                // Check if PetClinic deployment exists
                def petclinicDeploymentExists = sh(script: "kubectl get deployment -n prod petclinic-app-prod", returnStatus: true) == 0
                if (!petclinicDeploymentExists) {
                    // First-time deployment: apply both service and deployment
                    echo "Deploying PetClinic service and deployment for the first time."
                    unstash 'source-code'

                    // Configure AWS region and update kubeconfig for EKS
                    sh """
                    aws configure set region ${AWS_REGION_EKS}
                    aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                    kubectl apply -f k8s/petclinic-service.yaml -n prod
                    kubectl apply -f k8s/petclinic-deployment.yaml -n prod
                    """
                } else {
                    // Update only the Docker image without reapplying the entire deployment
                    echo "PetClinic deployment already exists. Updating the image if needed."

                    // Get the current image of the deployment
                    def currentImage = sh(script: "kubectl get deployment petclinic-app-prod -n prod -o jsonpath='{.spec.template.spec.containers[0].image}'", returnStdout: true).trim()

                    // If the current image is different from the new image, update the deployment
                    if (currentImage != "${env.DOCKER_IMAGE}") {
                        echo "Updating the Docker image from ${currentImage} to ${env.DOCKER_IMAGE}"

                        // Use kubectl set image to update only the image, avoiding environment variable conflicts
                        sh """
                        aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                        kubectl set image deployment/petclinic-app-prod petclinic=${env.DOCKER_IMAGE} -n prod
                        """
                    } else {
                        echo "The Docker image is already up to date: ${currentImage}"
                    }
                }
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
                            def runningPods = sh(script: "kubectl get pod -n prod -l app=petclinic -o jsonpath='{.items[*].status.phase}' | grep -o 'Running' | wc -l", returnStdout: true).trim()
                            def totalPods = sh(script: "kubectl get pod -n prod -l app=petclinic --no-headers | wc -l", returnStdout: true).trim()
                            if (runningPods.toInteger() == totalPods.toInteger()) {
                                allPodsReady = true
                                echo "All PetClinic pods are healthy and running."
                                break
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

        stage('Run JMeter Performance Tests') {
            steps {
                script {
                    sh "mkdir -p jmeter-results"
                    sh """
                    ${JMETER_HOME}/bin/jmeter -n \
                    -t ${JMETER_SCRIPT} \
                    -l ${JMETER_RESULTS} \
                    -e -o ${JMETER_REPORT}
                    """
                }
            }
        }
        
        stage('Smoke Tests') {
            steps {
                sh 'chmod +x ./scripts/run-smoke-tests.sh'
                sh './scripts/run-smoke-tests.sh'
            }
        }

        stage('Archive JMeter Results') {
            steps {
                archiveArtifacts artifacts: 'jmeter-results/results.jtl', allowEmptyArchive: false
                publishHTML(target: [
                    reportName : 'JMeter Performance Report',
                    reportDir  : 'jmeter-results/report',
                    reportFiles: 'index.html',
                    alwaysLinkToLastBuild: true,
                    keepAll    : true
                ])
            }
        }

        stage('Send Email Report') {
            steps {
                emailext (
                    subject: "JMeter Performance Test Report - ${currentBuild.fullDisplayName}",
                    body: "Please find the attached JMeter performance test report for the ${env.JOB_NAME}.",
                    attachLog: true,
                    attachmentsPattern: 'jmeter-results/report/index.html',
                    to: "ssrmca07@gmail.com, nagaraju.kjkc@gmail.com"
                )
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
            Scan reports have been emailed.
            """)
        }
        failure {
            slackSend(channel: '#project-petclinic', color: 'danger', message: """
            FAILURE: Job '${env.JOB_NAME}' build #${currentBuild.number} failed.
            """)
        }
        unstable {
            slackSend(channel: '#project-petclinic', color: 'warning', message: """
            UNSTABLE: Job '${env.JOB_NAME}' build #${currentBuild.number} is unstable.
            """)
        }
    }
}
