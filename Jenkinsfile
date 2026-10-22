
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        skipDefaultCheckout(true)
    }

    parameters {
        choice(
            name: 'BUILD_MODE',
            choices: ['FULL', 'TEST_ONLY'],
            description: 'FULL builds, tests, pushes and deploys. TEST_ONLY validates and tests locally.'
        )
    }

    environment {
        DOCKERHUB_USERNAME = 'bbhavanasree'
        IMAGE_NAME = 'bbhavanasree/ewaste-portal'

        DOCKER_CREDENTIALS_ID = 'dockerhub-creds'
        KUBECONFIG_CREDENTIALS_ID = 'kubernetes-creds'

        K8S_DEPLOYMENT = 'ewaste-portal-deployment'
        K8S_CONTAINER = 'ewaste-portal'
        K8S_SERVICE = 'ewaste-portal-service'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                bat 'git log -1 --oneline'
            }
        }

        stage('Parallel Validation') {
            parallel {
                stage('HTML Validation') {
                    steps {
                        bat 'if not exist index.html exit /b 1'
                        bat 'findstr /C:"Central Civic Collection Centre" index.html'
                        bat 'findstr /C:"Successfully recycled" index.html'
                        bat 'findstr /C:"scheduleForm" index.html'
                    }
                }

                stage('Docker and Kubernetes File Validation') {
                    steps {
                        bat 'if not exist Dockerfile exit /b 1'
                        bat 'if not exist deployment.yaml exit /b 1'

                        powershell '''
                            $ErrorActionPreference = "Stop"

                            $yaml = Get-Content "deployment.yaml" -Raw

                            if ($yaml -notmatch '(?m)^kind:\\s*Deployment\\s*$') {
                                throw "Deployment resource is missing from deployment.yaml."
                            }

                            if ($yaml -notmatch '(?m)^kind:\\s*Service\\s*$') {
                                throw "Service resource is missing from deployment.yaml."
                            }

                            Write-Host "Deployment and Service declarations found."
                        '''
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    env.IMAGE_TAG = "build-${env.BUILD_NUMBER}"

                    bat "docker build -t ${env.IMAGE_NAME}:${env.IMAGE_TAG} ."

                    bat "docker image inspect ${env.IMAGE_NAME}:${env.IMAGE_TAG} > image-inspect.json"
                }
            }
        }

        stage('Local Container Smoke Test') {
            steps {
                script {
                    bat 'docker rm -f ewaste-smoke >NUL 2>&1 || exit /b 0'

                    try {
                        bat "docker run -d --name ewaste-smoke -p 18087:80 ${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                        bat '''
                            powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0;$i -lt 15;$i++){try{$r=Invoke-WebRequest -UseBasicParsing http://localhost:18087; if($r.StatusCode -eq 200 -and $r.Content.Contains('Central Civic Collection Centre')){$ok=$true;break}}catch{}; Start-Sleep -Seconds 2}; if(-not $ok){docker logs ewaste-smoke; exit 1}"
                        '''
                    } finally {
                        bat 'docker rm -f ewaste-smoke >NUL 2>&1 || exit /b 0'
                    }
                }
            }
        }

        stage('Archive Build Artifacts') {
            steps {
                archiveArtifacts(
                    artifacts: 'index.html,Dockerfile,Jenkinsfile,deployment.yaml,image-inspect.json',
                    fingerprint: true
                )
            }
        }

        stage('Push Image to Docker Hub') {
            when {
                expression {
                    return params.BUILD_MODE == 'FULL'
                }
            }

            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'dockerhub-creds',
                        usernameVariable: 'DH_USER',
                        passwordVariable: 'DH_TOKEN'
                    )
                ]) {
                    script {
                        int loginStatus = powershell(
                            returnStatus: true,
                            script: '''
                                $ErrorActionPreference = "Stop"

                                $psi = New-Object System.Diagnostics.ProcessStartInfo
                                $psi.FileName = "docker"
                                $psi.Arguments = "login --username $env:DH_USER --password-stdin"
                                $psi.UseShellExecute = $false
                                $psi.RedirectStandardInput = $true
                                $psi.RedirectStandardOutput = $true
                                $psi.RedirectStandardError = $true
                                $psi.CreateNoWindow = $true

                                $p = New-Object System.Diagnostics.Process
                                $p.StartInfo = $psi
                                [void]$p.Start()

                                $p.StandardInput.WriteLine($env:DH_TOKEN)
                                $p.StandardInput.Close()

                                $out = $p.StandardOutput.ReadToEnd()
                                $err = $p.StandardError.ReadToEnd()
                                $p.WaitForExit()

                                if ($out) { Write-Output $out }
                                if ($err) { Write-Output $err }

                                exit $p.ExitCode
                            '''
                        )

                        if (loginStatus != 0) {
                            error('Docker Hub login failed. Check the existing dockerhub-creds credential.')
                        }

                        try {
                            bat "docker push ${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                            bat "docker tag ${env.IMAGE_NAME}:${env.IMAGE_TAG} ${env.IMAGE_NAME}:latest"

                            bat "docker push ${env.IMAGE_NAME}:latest"
                        } finally {
                            bat 'docker logout'
                        }
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when {
                expression {
                    return params.BUILD_MODE == 'FULL'
                }
            }

            steps {
                withCredentials([
                    file(
                        credentialsId: 'kubernetes-creds',
                        variable: 'KUBECONFIG'
                    )
                ]) {
                    bat 'kubectl version --client'
                    bat 'kubectl cluster-info'

                    bat 'kubectl apply -f deployment.yaml'

                    bat "kubectl set image deployment/${env.K8S_DEPLOYMENT} ${env.K8S_CONTAINER}=${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                    script {
                        int rolloutStatus = bat(
                            returnStatus: true,
                            script: "kubectl rollout status deployment/${env.K8S_DEPLOYMENT} --timeout=120s"
                        )

                        if (rolloutStatus != 0) {
                            echo 'Deployment failed. Collecting diagnostics.'

                            bat 'kubectl get pods -o wide'
                            bat "kubectl describe deployment ${env.K8S_DEPLOYMENT}"
                            bat "kubectl rollout history deployment/${env.K8S_DEPLOYMENT}"

                            int undoStatus = bat(
                                returnStatus: true,
                                script: "kubectl rollout undo deployment/${env.K8S_DEPLOYMENT}"
                            )

                            if (undoStatus != 0) {
                                error('Deployment failed and rollback could not be initiated.')
                            }

                            int recoveryStatus = bat(
                                returnStatus: true,
                                script: "kubectl rollout status deployment/${env.K8S_DEPLOYMENT} --timeout=120s"
                            )

                            if (recoveryStatus != 0) {
                                error('Rollback was requested, but the previous revision did not become healthy.')
                            }

                            error('Deployment failed. The previous revision was restored.')
                        }

                        bat "kubectl get deployment ${env.K8S_DEPLOYMENT}"
                        bat "kubectl get pods"
                        bat "kubectl get service ${env.K8S_SERVICE}"

                        echo 'Deployment completed successfully.'
                    }
                }
            }
        }
    }

    post {
        always {
            bat 'docker rm -f ewaste-smoke >NUL 2>&1 || exit /b 0'
            echo 'Pipeline finished. Review the stage logs.'
        }
    }
}
