
pipeline {
    agent any

    parameters {
        choice(
            name: 'BUILD_MODE',
            choices: ['FULL', 'TEST_ONLY'],
            description: 'FULL runs all stages; TEST_ONLY builds and tests.'
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

                    $yaml = Get-Content "deployment.yaml" -Raw

                    if ($yaml -notmatch '(?m)^kind:\\s*Deployment\\s*$') {
                        throw "Deployment resource missing in deployment.yaml"
                    }

                    if ($yaml -notmatch '(?m)^kind:\\s*Service\\s*$') {
                        throw "Service resource missing in deployment.yaml"
                    }

                    if ($yaml -notmatch 'ewaste-portal') {
                        throw "Expected E-Waste portal name not found"
                    }

                    Write-Host "Local Kubernetes manifest checks passed."
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
                                    -UseBasicParsing -TimeoutSec 3

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

                        $dockerConfig = Join-Path $env:WORKSPACE ".docker-auth-$env:BUILD_NUMBER"
                        New-Item -ItemType Directory -Force -Path $dockerConfig |
                            Out-Null
                        $env:DOCKER_CONFIG = $dockerConfig

                        try {
                            $psi = New-Object System.Diagnostics.ProcessStartInfo
                            $psi.FileName = (Get-Command docker.exe -ErrorAction Stop).Source
                            $psi.Arguments = "login --username $env:DOCKER_USER --password-stdin"
                            $psi.UseShellExecute = $false
                            $psi.CreateNoWindow = $true
                            $psi.RedirectStandardInput = $true
                            $psi.RedirectStandardOutput = $true
                            $psi.RedirectStandardError = $true

                            $proc = New-Object System.Diagnostics.Process
                            $proc.StartInfo = $psi
                            [void]$proc.Start()

                            $outTask = $proc.StandardOutput.ReadToEndAsync()
                            $errTask = $proc.StandardError.ReadToEndAsync()

                            $proc.StandardInput.WriteLine($env:DOCKER_PASS)
                            $proc.StandardInput.Close()
                            $proc.WaitForExit()

                            if ($outTask.Result) {
                                Write-Host $outTask.Result
                            }

                            if ($proc.ExitCode -ne 0) {
                                if ($errTask.Result) {
                                    Write-Host $errTask.Result
                                }
                                throw "Docker Hub login failed."
                            }

                            Write-Host "Docker Hub login successful."

                            docker push "$env:IMAGE_NAME`:$env:BUILD_NUMBER"
                            if ($LASTEXITCODE -ne 0) {
                                throw "Versioned image push failed."
                            }

                            docker push "$env:IMAGE_NAME`:latest"
                            if ($LASTEXITCODE -ne 0) {
                                throw "Latest image push failed."
                            }

                            Write-Host "Docker Hub push successful."
                        }
                        finally {
                            docker logout 2>$null | Out-Null
                            Remove-Item $dockerConfig -Recurse -Force `
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

                        kubectl cluster-info
                        if ($LASTEXITCODE -ne 0) {
                            throw "Cannot connect to Kubernetes. Check cluster and kubeconfig."
                        }

                        kubectl apply -f deployment.yaml
                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes manifest apply failed."
                        }

                        $newImage = "$env:IMAGE_NAME`:$env:BUILD_NUMBER"

                        kubectl set image `
                            "deployment/$env:K8S_DEPLOYMENT" `
                            "$env:K8S_CONTAINER=$newImage"

                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes image update failed."
                        }

                        kubectl rollout status `
                            "deployment/$env:K8S_DEPLOYMENT" `
                            --timeout=120s

                        if ($LASTEXITCODE -ne 0) {
                            throw "Kubernetes rollout failed."
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
            echo 'FAILED: Check the first failing stage in Console Output.'
        }
        always {
            echo 'E-Waste pipeline finished.'
        }
    }
}
