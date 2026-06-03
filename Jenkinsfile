pipeline {

    agent {
        docker {
            image 'python:3.11'
            args '''
                -u root \
                -v /var/run/docker.sock:/var/run/docker.sock
            '''
        }
    }

    environment {
        AWS_REGION = "ap-south-1"
        IMAGE_TAG  = "${env.BUILD_NUMBER}"
        IMAGE_NAME = "711387119594.dkr.ecr.ap-south-1.amazonaws.com/moveinsync:${IMAGE_TAG}"
    }

    stages {

        // ── 1. Checkout ─────────────────────────────────────
        stage('Git Checkout') {
            steps {
                git url: 'https://github.com/amithachar/MoveInSync.git', branch: 'main'
            }
        }

        // ── Install Docker CLI ──────────────────────────────
        stage('Install Docker CLI') {
            steps {
                sh '''
                    apt-get update

                    apt-get install -y \
                        docker.io \
                        awscli

                    echo "Docker:"
                    docker --version

                    echo "AWS:"
                    aws --version
                '''
            }
        }

        // ── 2. Install Dependencies ─────────────────────────
        stage('Install Dependencies') {
            steps {
                sh '''
                    python -m pip install --upgrade pip
                    pip install --quiet -r requirements.txt
                    pip install --quiet -r requirements-test.txt
                '''
            }
        }

        // ── 3. Unit Tests & Coverage ────────────────────────
        stage('Unit Tests & Coverage') {
            steps {
                sh '''
                    pytest tests/ \
                        --cov=. \
                        --cov-report=xml:coverage.xml \
                        --cov-report=term-missing \
                        --junitxml=test-results.xml \
                        -v
                '''
            }

            post {
                always {
                    junit 'test-results.xml'
                }
            }
        }

        // ── 4. SonarQube ────────────────────────────────────
        /*
        stage('SonarQube Analysis') {
            steps {
                sh '''
                    docker run --rm \
                        -e SONAR_HOST_URL=http://52.66.76.231:9000 \
                        -e SONAR_LOGIN="92ff3f2b213a8f1bdcbccd72a266b34a98cd1cbc" \
                        -v $(pwd):/usr/src \
                        sonarsource/sonar-scanner-cli \
                        -Dsonar.projectKey=test \
                        -Dsonar.sources=.
                '''
            }
        }
        */

        // ── 5. Quality Gate ─────────────────────────────────
        /*
        stage('Quality Gate') {
            steps {
                timeout(time: 2, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }
        */

        // ── 6. Dependency Vulnerability Scan ────────────────
        stage('Dependency Vulnerability Scan') {
            steps {
                sh '''
                    pip install pip-audit

                    pip-audit -r requirements.txt \
                        --format=json \
                        -o pip-audit-report.json || true

                    pip-audit -r requirements.txt
                '''
            }

            post {
                always {
                    archiveArtifacts artifacts: 'pip-audit-report.json', allowEmptyArchive: true
                }
            }
        }

        // ── 7. Security Scan & Docker Build ─────────────────
        stage('Security Scan & Docker Build') {

            parallel {

                stage('Trivy Base Image Scan') {
                    steps {
                        sh 'bash trivy-docker-image-scan.sh'
                    }
                }

                stage('OPA Dockerfile Rules') {
                    steps {
                        sh '''
                            docker run --rm \
                                -v $(pwd):/project \
                                openpolicyagent/conftest \
                                test \
                                --policy dockerfile-security.rego \
                                Dockerfile
                        '''
                    }
                }

                stage('Docker Build') {
                    steps {
                        sh 'docker build -t moveinsync:latest .'
                    }
                }
            }
        }

        // ── 8. ECR Login ────────────────────────────────────
        stage('ECR Login') {
            steps {
                sh '''
                    aws ecr get-login-password --region $AWS_REGION \
                    | docker login \
                        --username AWS \
                        --password-stdin \
                        711387119594.dkr.ecr.$AWS_REGION.amazonaws.com
                '''
            }
        }

        // ── 9. Tag & Push ───────────────────────────────────
        stage('Tag for ECR') {
            steps {
                sh "docker tag moveinsync:latest $IMAGE_NAME"
            }
        }

        stage('Push to ECR') {
            steps {
                sh "docker push $IMAGE_NAME"
            }
        }

        // ── 10. OPA Kubernetes Rules ────────────────────────
        stage('OPA Kubernetes Rules') {
            steps {
                sh '''
                    docker run --rm \
                        -v $(pwd):/project \
                        openpolicyagent/conftest \
                        test \
                        --policy opa-k8s-security.rego \
                        deployment.yml
                '''
            }
        }

        // ── 11. GitOps Update ───────────────────────────────
        stage('Update GitOps Deployment') {

            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'github-creds',
                        usernameVariable: 'GIT_USERNAME',
                        passwordVariable: 'GIT_PASSWORD'
                    )
                ]) {

                    sh '''
                        rm -rf MoveInSync-gitops || true

                        git clone \
                        https://$GIT_USERNAME:$GIT_PASSWORD@github.com/amithachar/MoveInSync-gitops.git

                        cd MoveInSync-gitops/moveinsync

                        git config user.email "jenkins@ci.com"
                        git config user.name "jenkins"

                        sed -i \
                        "s|image: .*moveinsync.*|image: ${IMAGE_NAME}|g" \
                        deployment.yaml

                        if ! git diff --quiet; then
                            git add deployment.yaml
                            git commit -m "Update moveinsync image to ${IMAGE_NAME}"
                            git push origin main
                        else
                            echo "No changes detected"
                        fi
                    '''
                }
            }
        }
    }

    post {

        always {
            archiveArtifacts \
                artifacts: 'coverage.xml,test-results.xml',
                allowEmptyArchive: true

            sh "docker rmi $IMAGE_NAME || true"
            sh "docker logout || true"
        }

        success {
            echo "Pipeline succeeded: ${IMAGE_NAME}"
        }

        failure {
            echo "Pipeline failed. Check logs."
        }
    }
}