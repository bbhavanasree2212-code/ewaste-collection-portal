
pipeline {
    agent any

    parameters {
        choice(
            name: 'BUILD_MODE',
            choices: ['FULL', 'TEST_ONLY'],
            description: 'FULL builds, tests, pushes and deploys. TEST_ONLY builds and tests only.'
        )
    }

    environment {
        IMAGE_NAME = 'bbhavanasree/ewaste-portal'
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
                    $ErrorActionPreference = "Stop"

                    if (!(Test-Path "index.html")) {
                        throw "index.html not found"
                    }

                    $html = Get-Content "index.html" -Raw

                    if ($html -notmatch "<html") {
                        throw "HTML validation failed"
                    }

                    Write-Host "HTML validation successful"
                '''
            }
        }

        stage('Validate Kubernetes YAML') {
            steps {
                powershell '''
                    $ErrorActionPreference = "Stop"

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
                archiveArtifacts(
                    artifacts: 'index.html,Dockerfile,deployment.yaml,Jenkinsfile',
                    allowEmptyArchive: true
                )
            }
        }

        stage('Build Docker Image') {
            steps {
                bat '''
                    docker build -t %IMAGE_NAME%:%BUILD_NUMBER% .
                    if errorlevel 1 exit /b 1

                    docker tag %IMAGE_NAME%:%BUILD_NUMBER% %IMAGE_NAME%:latest
                    if errorlevel 1 exit /b 1
                '''
            }
        }

        stage('Test Docker Image') {
            steps {
                powershell '''
                    $ErrorActionPreference = "Stop"

                    $containerName = "ewaste-test-$env:BUILD_NUMBER"
                    $image = "$env:IMAGE_NAME`:$env:BUILD_NUMBER"

                    docker rm -f $containerName 2>$null | Out-Null

                    docker run -d --name $containerName -p 18080:80 $image

                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker container failed to start"
                    }

                    try {
                        $passed = $false

                        for ($i = 0; $i -lt 10; $i++) {
                            try {
                                $response = Invoke-WebRequest `
                                    -Uri "http://127.0.0.1:18080" `
                                    -UseBasicParsing `
                                    -TimeoutSec 3

                                if ($response.StatusCode -eq 200) {
                                    $passed = $true
                                    break
                                }
                            }
                            catch {
                                Start-Sleep -Seconds 2
                            }
                        }

                        if (!$passed) {
                            throw "Website HTTP test failed"
                        }

                        Write-Host "Website HTTP test passed: HTTP 200"
                    }
                    finally {
                        docker rm -f $containerName | Out-Null
                    }
                '''
            }
        }

        stage('Push to Docker Hub') {
            when {
                expression { params.BUILD_MODE == 'FULL' }
            }

            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )
                ]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"

                        # Isolated Docker configuration for this Jenkins build
                        $dockerConfig = Join-Path $env:WORKSPACE ".docker-$env:BUILD_NUMBER"

                        New-Item -ItemType Directory -Path $dockerConfig -Force |
                            Out-Null

                        $env:DOCKER_CONFIG = $dockerConfig

                        try {
                            # Pass the existing Jenkins credential securely via stdin
                            $env:DOCKER_PASS |
                                docker login --username $env:DOCKER_USER --password-stdin

                            if ($LASTEXITCODE -ne 0) {
                                throw "Docker Hub login failed"
                            }

                            docker push "$env:IMAGE_NAME`:$env:BUILD_NUMBER"

                            if ($LASTEXITCODE -ne 0) {
                                throw "Failed to push versioned image"
                            }

                            docker push "$env:IMAGE_NAME`:latest"

                            if ($LASTEXITCODE -ne 0) {
                                throw "Failed to push latest image"
                            }

                            Write-Host "Docker images pushed successfully"
                        }
                        finally {
                            docker logout 2>$null | Out-Null

                            Remove-Item -Path $dockerConfig `
                                -Recurse -Force `
                                -ErrorAction SilentlyContinue
                        }
                    '''
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when {
                expression { params.BUILD_MODE == 'FULL' }
            }

            steps {
                withCredentials([
                    file(
                        credentialsId: 'kubernetes-creds',
                        variable: 'KUBECONFIG_FILE'
                    )
                ]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"

                        $env:KUBECONFIG = $env:KUBECONFIG_FILE

                        kubectl apply -f deployment.yaml

                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes apply failed"
                        }

                        $newImage = "$env:IMAGE_NAME`:$env:BUILD_NUMBER"

                        kubectl set image `
                            "deployment/$env:K8S_DEPLOYMENT" `
                            "$env:K8S_CONTAINER=$newImage"

                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes image update failed"
                        }

                        kubectl rollout status `
                            "deployment/$env:K8S_DEPLOYMENT" `
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
            echo 'SUCCESS: E-Waste pipeline completed successfully.'
        }

        failure {
            echo 'FAILED: Check the stage error in Console Output.'
        }

        always {
            echo 'E-Waste pipeline finished.'
        }
    }
}
