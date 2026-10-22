
pipeline {
    agent any

    parameters {
        choice(
            name: 'BUILD_MODE',
            choices: ['FULL', 'TEST_ONLY'],
            description: 'FULL builds and deploys. TEST_ONLY runs checks and archives files.'
        )
    }

    environment {
        DOCKER_IMAGE = 'bbhavanasree/ewaste-portal'
        K8S_DEPLOYMENT = 'ewaste-portal-deployment'
        K8S_CONTAINER = 'ewaste-portal'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo 'Latest repository code checked out.'
            }
        }

        stage('Parallel Validation') {
            parallel {
                stage('Validate HTML') {
                    steps {
                        powershell '''
                            if (!(Test-Path "index.html")) {
                                throw "index.html is missing"
                            }
                            $html = Get-Content "index.html" -Raw
                            if ($html -notmatch "<html" -or
                                $html -notmatch "</html>") {
                                throw "HTML validation failed"
                            }
                            Write-Output "HTML validation passed"
                        '''
                    }
                }

                stage('Validate Kubernetes YAML') {
                    steps {
                        powershell '''
                            if (!(Test-Path "deployment.yaml")) {
                                throw "deployment.yaml is missing"
                            }
                            $yaml = Get-Content "deployment.yaml" -Raw
                            if ($yaml -notmatch "kind: Deployment" -or
                                $yaml -notmatch "kind: Service") {
                                throw "Kubernetes manifest validation failed"
                            }
                            Write-Output "Kubernetes manifest checks passed"
                        '''
                    }
                }
            }
        }

        stage('Archive Build Artifacts') {
            steps {
                archiveArtifacts artifacts: 'index.html,Dockerfile,deployment.yaml,Jenkinsfile',
                                 fingerprint: true
            }
        }

        stage('Build Docker Image') {
            when {
                expression { params.BUILD_MODE == 'FULL' }
            }
            steps {
                bat 'docker build -t %DOCKER_IMAGE%:%BUILD_NUMBER% .'
                bat 'docker tag %DOCKER_IMAGE%:%BUILD_NUMBER% %DOCKER_IMAGE%:latest'
            }
        }

        stage('Test Docker Image') {
            when {
                expression { params.BUILD_MODE == 'FULL' }
            }
            steps {
                powershell '''
                    $image = "$env:DOCKER_IMAGE`:$env:BUILD_NUMBER"
                    docker run -d --name ewaste-test -p 18080:80 $image
                    if ($LASTEXITCODE -ne 0) {
                        throw "Docker container failed to start"
                    }

                    try {
                        $response = $null
                        for ($i = 0; $i -lt 10; $i++) {
                            try {
                                $response = Invoke-WebRequest `
                                    -Uri "http://localhost:18080" `
                                    -UseBasicParsing
                                break
                            } catch {
                                Start-Sleep -Seconds 2
                            }
                        }

                        if ($null -eq $response -or $response.StatusCode -ne 200) {
                            throw "Portal HTTP test failed"
                        }
                        Write-Output "Portal HTTP test passed"
                    } finally {
                        docker rm -f ewaste-test
                    }
                '''
            }
        }

        stage('Push Image to Docker Hub') {
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
                        $env:DOCKER_PASS | docker login `
                            --username $env:DOCKER_USER --password-stdin
                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker Hub login failed"
                        }

                        docker push "$env:DOCKER_IMAGE`:$env:BUILD_NUMBER"
                        if ($LASTEXITCODE -ne 0) {
                            throw "Docker image push failed"
                        }

                        docker push "$env:DOCKER_IMAGE`:latest"
                        if ($LASTEXITCODE -ne 0) {
                            throw "Latest image push failed"
                        }

                        docker logout
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
                    file(credentialsId: 'kubernetes-creds', variable: 'KUBECONFIG_FILE')
                ]) {
                    powershell '''
                        $env:KUBECONFIG = $env:KUBECONFIG_FILE

                        kubectl apply -f deployment.yaml
                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes manifest apply failed"
                        }

                        kubectl set image `
                            deployment/ewaste-portal-deployment `
                            ewaste-portal="$env:DOCKER_IMAGE`:$env:BUILD_NUMBER"

                        if ($LASTEXITCODE -ne 0) {
                            throw "Could not update Kubernetes image"
                        }

                        kubectl rollout status `
                            deployment/ewaste-portal-deployment `
                            --timeout=180s

                        if ($LASTEXITCODE -ne 0) {
                            throw "Deployment rollout failed"
                        }
                    '''
                }
            }
        }

        stage('Test Failed Rollout and Roll Back') {
            when {
                expression { params.BUILD_MODE == 'FULL' }
            }
            steps {
                withCredentials([
                    file(credentialsId: 'kubernetes-creds', variable: 'KUBECONFIG_FILE')
                ]) {
                    powershell '''
                        $env:KUBECONFIG = $env:KUBECONFIG_FILE

                        Write-Output "Injecting an invalid image to test rollback..."

                        kubectl set image `
                            deployment/ewaste-portal-deployment `
                            ewaste-portal="$env:DOCKER_IMAGE`:deliberately-broken"

                        if ($LASTEXITCODE -ne 0) {
                            throw "Could not create the test rollout"
                        }

                        kubectl rollout status `
                            deployment/ewaste-portal-deployment `
                            --timeout=60s

                        $rolloutResult = $LASTEXITCODE

                        if ($rolloutResult -eq 0) {
                            throw "Expected the deliberately broken rollout to fail"
                        }

                        Write-Output "Broken rollout detected. Rolling back..."

                        kubectl rollout undo deployment/ewaste-portal-deployment
                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes rollback command failed"
                        }

                        kubectl rollout status `
                            deployment/ewaste-portal-deployment `
                            --timeout=180s

                        if ($LASTEXITCODE -ne 0) {
                            throw "Rollback did not become healthy"
                        }

                        kubectl get deployment ewaste-portal-deployment
                        kubectl get pods -l app=ewaste-portal
                        Write-Output "Rollback completed and stable rollout recovered."
                    '''
                }
            }
        }
    }

    post {
        always {
            echo 'E-Waste portal pipeline finished. Review the stage results.'
        }
    }
}
