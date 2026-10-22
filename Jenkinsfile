
pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'bbhavanasree/ewaste-portal'
        K8S_DEPLOYMENT = 'ewaste-portal-deployment'
        K8S_CONTAINER = 'ewaste-portal'
    }

    stages {
        stage('Checkout') {
            steps {
                git branch: 'main',
                    url: 'https://github.com/bbhavanasree2212-code/ewaste-collection-portal.git'
            }
        }

        stage('Validate HTML') {
            steps {
                powershell '''
                    if (!(Test-Path "index.html")) {
                        throw "index.html not found"
                    }

                    $html = Get-Content "index.html" -Raw
                    if ($html -notmatch "<html") {
                        throw "Invalid HTML file"
                    }

                    Write-Host "HTML validation successful"
                '''
            }
        }

        stage('Validate Kubernetes YAML') {
            steps {
                powershell '''
                    if (!(Test-Path "deployment.yaml")) {
                        throw "deployment.yaml not found"
                    }

                    kubectl apply --dry-run=client -f deployment.yaml
                    if ($LASTEXITCODE -ne 0) {
                        throw "Kubernetes YAML validation failed"
                    }

                    Write-Host "Kubernetes YAML validation successful"
                '''
            }
        }

        stage('Archive Artifacts') {
            steps {
                archiveArtifacts artifacts: 'index.html,Dockerfile,deployment.yaml,Jenkinsfile',
                    allowEmptyArchive: true
            }
        }

        stage('Build Docker Image') {
            steps {
                bat '''
                    docker build -t %DOCKER_IMAGE%:%BUILD_NUMBER% .
                    if errorlevel 1 exit /b 1

                    docker tag %DOCKER_IMAGE%:%BUILD_NUMBER% %DOCKER_IMAGE%:latest
                    if errorlevel 1 exit /b 1
                '''
            }
        }

        stage('Test Docker Image') {
            steps {
                powershell '''
                    $ErrorActionPreference = "Stop"
                    $container = "ewaste-test-$env:BUILD_NUMBER"
                    $image = "$env:DOCKER_IMAGE`:$env:BUILD_NUMBER"

                    docker rm -f $container 2>$null | Out-Null

                    docker run -d --name $container -p 18080:80 $image
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker container failed to start"
                    }

                    try {
                        $success = $false

                        for ($i = 0; $i -lt 10; $i++) {
                            try {
                                $response = Invoke-WebRequest `
                                    -Uri "http://localhost:18080" `
                                    -UseBasicParsing -TimeoutSec 3

                                if ($response.StatusCode -eq 200) {
                                    $success = $true
                                    break
                                }
                            } catch {
                                Start-Sleep -Seconds 2
                            }
                        }

                        if (!$success) {
                            throw "Website HTTP test failed"
                        }

                        Write-Host "Website HTTP test successful"
                    }
                    finally {
                        docker rm -f $container | Out-Null
                    }
                '''
            }
        }

        stage('Push to Docker Hub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"

                        # Keep Docker authentication separate for this build.
                        $config = Join-Path $env:WORKSPACE ".docker-config-$env:BUILD_NUMBER"
                        New-Item -ItemType Directory -Force -Path $config | Out-Null
                        $env:DOCKER_CONFIG = $config

                        try {
                            $env:DOCKER_PASS | docker login `
                                --username $env:DOCKER_USER `
                                --password-stdin

                            if ($LASTEXITCODE -ne 0) {
                                throw "Docker Hub login failed. Check the Jenkins console error."
                            }

                            docker push "$env:DOCKER_IMAGE`:$env:BUILD_NUMBER"
                            if ($LASTEXITCODE -ne 0) {
                                throw "Versioned image push failed"
                            }

                            docker push "$env:DOCKER_IMAGE`:latest"
                            if ($LASTEXITCODE -ne 0) {
                                throw "Latest image push failed"
                            }

                            Write-Host "Docker Hub push successful"
                        }
                        finally {
                            docker logout 2>$null | Out-Null
                            Remove-Item -Recurse -Force $config -ErrorAction SilentlyContinue
                        }
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([file(
                    credentialsId: 'kubernetes-creds',
                    variable: 'KUBECONFIG_FILE'
                )]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"
                        $env:KUBECONFIG = $env:KUBECONFIG_FILE

                        kubectl apply -f deployment.yaml
                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes apply failed"
                        }

                        kubectl set image `
                            deployment/$env:K8S_DEPLOYMENT `
                            $env:K8S_CONTAINER="$env:DOCKER_IMAGE`:$env:BUILD_NUMBER"

                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes image update failed"
                        }

                        kubectl rollout status `
                            deployment/$env:K8S_DEPLOYMENT `
                            --timeout=120s

                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes rollout failed"
                        }

                        kubectl get deployments
                        kubectl get services
                        kubectl get pods
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'SUCCESS: E-Waste Portal built, tested, pushed, and deployed.'
        }

        failure {
            echo 'FAILED: Check the first error in the Jenkins Console Output.'
        }

        always {
            echo 'E-Waste Portal pipeline finished.'
        }
    }
}
