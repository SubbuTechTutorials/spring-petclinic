pipeline {
    agent any

    tools {
        jdk 'JDK 17'  // Make sure this matches your Jenkins JDK configuration
        maven 'maven 3.9.8'  // Ensure this matches the Maven setup in Global Tool Configuration
    }

    environment {
        GIT_REPO = 'https://github.com/SubbuTechTutorials/spring-petclinic.git'
        GIT_BRANCH = 'develop'
        GIT_CREDENTIALS_ID = 'github-credentials'
        TRIVY_PAT_CREDENTIALS_ID = 'github-pat'
        
        // SonarQube settings
        SONARQUBE_HOST_URL = 'http://44.201.120.105:9000/'  // Replace with your SonarQube URL
        SONARQUBE_PROJECT_KEY = 'PetClinic'
        SONARQUBE_TOKEN = credentials('sonar-credentials')  // Ensure this matches your credentials
        
        // EKS Cluster name and region
        EKS_CLUSTER_NAME = 'devops-petclinicapp-dev-ap-south-1'
        AWS_REGION_EKS = 'ap-south-1'
        
        // Set local directory to cache Trivy DB
        TRIVY_DB_CACHE = "/var/lib/jenkins/trivy-db"

        // Slack environment variables
        SLACK_CHANNEL = '#project-petclinic'  // Replace with your Slack channel
    }

    options {
        skipStagesAfterUnstable()  // Skip stages if a previous stage fails
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
                            def dbAge = sh(script: "find ${TRIVY_DB_CACHE} -name 'db.lock' -mtime +7 | wc -l", returnStdout: true).trim()
                            if (dbAge != '1') {
                                sh "trivy fs --cache-dir ${TRIVY_DB_CACHE} --exit-code 1 --severity HIGH,CRITICAL --token $GITHUB_TOKEN ."
                            } else {
                                sh "trivy fs --cache-dir ${TRIVY_DB_CACHE} --skip-db-update --exit-code 1 --severity HIGH,CRITICAL ."
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

        // Manual Approval stage with Slack notification
        stage('Manual Approval') {
            steps {
                script {
                    // Send Slack notification when manual approval is needed
                    slackSend(channel: "${SLACK_CHANNEL}", color: 'warning', message: "Build #${env.BUILD_NUMBER} is waiting for manual approval. Please review: ${env.BUILD_URL}")

                    timeout(time: 10, unit: 'MINUTES') {
                        def approvalMailContent = """
                        Project: ${env.JOB_NAME}
                        Build Number: ${env.BUILD_NUMBER}
                        Go to build URL and approve the deployment request.
                        URL of build: ${env.BUILD_URL}
                        """
                        mail(
                            to: 'ssrmca07@gmail.com',
                            subject: "${currentBuild.result} CI: Project name -> ${env.JOB_NAME}", 
                            body: approvalMailContent,
                            mimeType: 'text/plain'
                        )
                        input(
                            id: "DeployGate",
                            message: "Deploy ${params.project_name}?",
                            submitter: "approver",
                            parameters: [choice(name: 'action', choices: ['Deploy'], description: 'Approve deployment')]
                        )

                        // Send Slack notification after approval
                        slackSend(channel: "${SLACK_CHANNEL}", color: 'good', message: "Build #${env.BUILD_NUMBER} was approved for deployment.")
                    }
                }
            }
        }

        stage('Deploy MySQL to EKS') {
            steps {
                script {
                    def mysqlDeploymentExists = sh(script: "kubectl get deployment -n dev mysql-db", returnStatus: true) == 0

                    if (!mysqlDeploymentExists) {
                        unstash 'source-code'
                        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                            sh """
                            aws configure set region ${AWS_REGION_EKS}
                            aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                            """
                            sh """
                                kubectl apply -f https://raw.githubusercontent.com/SubbuTechTutorials/spring-petclinic/develop/k8s/mysql-pvc.yaml
                                kubectl apply -f https://raw.githubusercontent.com/SubbuTechTutorials/spring-petclinic/develop/k8s/mysql-service.yaml
                                kubectl apply -f https://raw.githubusercontent.com/SubbuTechTutorials/spring-petclinic/develop/k8s/mysql-deployment.yaml
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
                        sh """
                        aws configure set region ${AWS_REGION_EKS}
                        aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                        """
                        
                        def maxRetries = 10
                        def retryInterval = 30
                        def isMySQLReady = 'false'

                        for (int i = 0; i < maxRetries; i++) {
                            echo "Checking MySQL readiness (Attempt ${i + 1}/${maxRetries})..."
                            isMySQLReady = sh(script: "kubectl get pod -n dev -l app=mysql -o jsonpath='{.items[0].status.containerStatuses[0].ready}'", returnStdout: true).trim()
                            if (isMySQLReady == 'true') {
                                echo 'MySQL service is ready. Proceeding with PetClinic deployment.'
                                break
                            } else {
                                echo "MySQL service is not ready. Waiting ${retryInterval} seconds before checking again..."
                                sleep retryInterval
                            }
                        }

                        if (isMySQLReady != 'true') {
                            error('MySQL service is still not ready after multiple attempts. Exiting deployment.')
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
                        aws configure set region ${AWS_REGION_EKS}
                        aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                        """

                        sh """
                            kubectl apply -f https://raw.githubusercontent.com/SubbuTechTutorials/spring-petclinic/develop/k8s/petclinic-deployment.yaml
                            kubectl apply -f https://raw.githubusercontent.com/SubbuTechTutorials/spring-petclinic/develop/k8s/petclinic-service.yaml
                         """
                    }
                }
            }
        }

        stage('Check PetClinic Health') {
            steps {
                script {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-eks-credentials']]) {
                        sh """
                        aws configure set region ${AWS_REGION_EKS}
                        aws eks --region ${AWS_REGION_EKS} update-kubeconfig --name ${EKS_CLUSTER_NAME}
                        """
                        
                        def maxRetries = 10
                        def retryInterval = 30
                        def isPetClinicReady = 'false'

                        for (int i = 0; i < maxRetries; i++) {
                            echo "Checking PetClinic health (Attempt ${i + 1}/${maxRetries})..."
                            def petclinicPodStatus = sh(script: "kubectl get pod -n dev -l app=petclinic -o jsonpath='{.items[0].status.phase}'", returnStdout: true).trim()
                            if (petclinicPodStatus == 'Running') {
                                echo 'PetClinic application is healthy.'
                                isPetClinicReady = 'true'
                                break
                            } else {
                                echo "PetClinic application is not ready yet. Waiting ${retryInterval} seconds before checking again..."
                                sleep retryInterval
                            }
                        }

                        if (isPetClinicReady != 'true') {
                            error('PetClinic application did not become healthy after multiple attempts.')
                        }
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
            slackSend(channel: '#project-petclinic', color: 'good', message: "SUCCESS: Job '${env.JOB_NAME}' build #${currentBuild.number} succeeded.")
        }
        failure {
            slackSend(channel: '#project-petclinic', color: 'danger', message: "FAILURE: Job '${env.JOB_NAME}' build #${currentBuild.number} failed.")
        }
        unstable {
            slackSend(channel: '#project-petclinic', color: 'warning', message: "UNSTABLE: Job '${env.JOB_NAME}' build #${currentBuild.number} is unstable.")
        }
    }
}
