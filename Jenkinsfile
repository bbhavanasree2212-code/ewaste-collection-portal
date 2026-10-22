
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
            name: 'RELEASE_MODE',
            choices: ['STABLE', 'FAULTY_ROLLBACK_TEST'],
            description: 'Choose a stable deployment or test rollback recovery.'
        )

        booleanParam(
            name: 'DEPLOY_TO_KUBERNETES',
            defaultValue: true,
            description: 'Deploy after the Docker image is pushed successfully.'
        )
    }

    environment {
        DOCKERHUB_USERNAME = 'bbhavanasree'
        IMAGE_NAME = 'ewaste-portal'
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
                stage('HTML Content Test') {
                    steps {
                        bat 'findstr /C:"Central Civic Collection Centre" index.html'
                        bat 'findstr /C:"Successfully recycled" index.html'
                        bat 'findstr /C:"scheduleForm" index.html'
                    }
                }

                stage('Deployment Manifest Test') {
                    steps {
                        bat 'findstr /C:"kind: Deployment" deployment.yaml'
                        bat 'findstr /C:"kind: Service" deployment.yaml'
                        bat 'findstr /C:"readinessProbe" deployment.yaml'
                        bat 'findstr /C:"ewaste-portal-deployment" deployment.yaml'
                        bat 'findstr /C:"ewaste-portal-service" deployment.yaml'
                    }
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    env.IMAGE_TAG = "v${env.BUILD_NUMBER}"

                    bat "docker build -t ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG} ."

                    bat "docker image inspect ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG} > image-inspect.json"
                }
            }
        }

        stage('Local Container Smoke Test') {
            steps {
                script {
                    bat 'docker rm -f e-waste-smoke >NUL 2>&1 || exit /b 0'

                    bat "docker run -d --name e-waste-smoke -p 18087:80 ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                    bat '''
                    powershell -NoProfile -ExecutionPolicy Bypass -Command "$ok=$false; for($i=0;$i -lt 15;$i++){try{$r=Invoke-WebRequest -UseBasicParsing http://localhost:18087; if($r.StatusCode -eq 200 -and $r.Content.Contains('Central Civic Collection Centre')){$ok=$true;break}}catch{}; Start-Sleep -Seconds 2}; if(-not $ok){docker logs e-waste-smoke; exit 1}"
                    '''

                    bat 'docker rm -f e-waste-smoke'
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

                                if ([string]::IsNullOrWhiteSpace($env:DH_USER)) {
                                    Write-Error "Docker Hub username is empty."
                                    exit 1
                                }

                                if ([string]::IsNullOrEmpty($env:DH_TOKEN)) {
                                    Write-Error "Docker Hub token is empty."
                                    exit 1
                                }

                                $psi = New-Object System.Diagnostics.ProcessStartInfo
                                $psi.FileName = "docker"
                                $psi.Arguments = "login --username $env:DH_USER --password-stdin"
                                $psi.UseShellExecute = $false
                                $psi.RedirectStandardInput = $true
                                $psi.RedirectStandardOutput = $true
                                $psi.RedirectStandardError = $true
                                $psi.CreateNoWindow = $true

                                $process = New-Object System.Diagnostics.Process
                                $process.StartInfo = $psi
                                [void]$process.Start()

                                $process.StandardInput.WriteLine($env:DH_TOKEN)
                                $process.StandardInput.Close()

                                $stdout = $process.StandardOutput.ReadToEnd()
                                $stderr = $process.StandardError.ReadToEnd()
                                $process.WaitForExit()

                                if ($stdout) { Write-Output $stdout }
                                if ($stderr) { Write-Output $stderr }

                                exit $process.ExitCode
                            '''
                        )

                        if (loginStatus != 0) {
                            error('Docker Hub login failed. Check the existing dockerhub-creds secret value and username without printing the token.')
                        }

                        try {
                            bat "docker push ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                            bat "docker tag ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG} ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:latest"

                            bat "docker push ${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:latest"
                        } finally {
                            bat 'docker logout'
                        }
                    }
                }
            }
        }

        stage('Deploy and Verify on Kubernetes') {
            when {
                expression {
                    return params.DEPLOY_TO_KUBERNETES
                }
            }

            steps {
                script {
                    withCredentials([
                        file(
                            credentialsId: 'kubernetes-creds',
                            variable: 'KUBECONFIG'
                        )
                    ]) {
                        bat 'kubectl version --client'
                        bat 'kubectl cluster-info'

                        bat 'kubectl apply -f deployment.yaml'

                        bat "kubectl set image deployment/${env.K8S_DEPLOYMENT} ${env.K8S_CONTAINER}=${env.DOCKERHUB_USERNAME}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"

                        if (params.RELEASE_MODE == 'FAULTY_ROLLBACK_TEST') {
                            echo 'Testing recovery from an intentionally faulty readiness probe.'

                            writeFile(
                                file: 'faulty-patch.json',
                                text: '''{
  "spec": {
    "template": {
      "spec": {
        "containers": [
          {
            "name": "ewaste-portal",
            "readinessProbe": {
              "httpGet": {
                "path": "/faulty-health-check",
                "port": 80
              },
              "initialDelaySeconds": 1,
              "periodSeconds": 3,
              "timeoutSeconds": 1,
              "failureThreshold": 2
            }
          }
        ]
      }
    }
  }
}'''
                            )

                            bat "kubectl patch deployment ${env.K8S_DEPLOYMENT} --type=strategic --patch-file=faulty-patch.json"

                            int faultyStatus = bat(
                                returnStatus: true,
                                script: "kubectl rollout status deployment/${env.K8S_DEPLOYMENT} --timeout=90s"
                            )

                            if (faultyStatus == 0) {
                                echo 'The faulty rollout unexpectedly became ready.'
                            } else {
                                echo 'The faulty rollout failed as expected. Checking deployment status.'
                            }

                            bat "kubectl get pods -o wide"
                            bat "kubectl describe deployment ${env.K8S_DEPLOYMENT}"
                            bat "kubectl rollout history deployment/${env.K8S_DEPLOYMENT}"

                            int undoStatus = bat(
                                returnStatus: true,
                                script: "kubectl rollout undo deployment/${env.K8S_DEPLOYMENT}"
                            )

                            if (undoStatus != 0) {
                                error('Rollback command failed. Check Kubernetes deployment history.')
                            }

                            int recoveryStatus = bat(
                                returnStatus: true,
                                script: "kubectl rollout status deployment/${env.K8S_DEPLOYMENT} --timeout=120s"
                            )

                            if (recoveryStatus != 0) {
                                error('Rollback was requested, but the previous revision did not become healthy.')
                            }

                            bat "kubectl get deployment ${env.K8S_DEPLOYMENT}"
                            bat "kubectl get pods"
                            bat "kubectl get service ${env.K8S_SERVICE}"

                            if (faultyStatus == 0) {
                                error('The faulty rollout unexpectedly passed. The previous revision was restored; review the probe configuration.')
                            }

                            echo 'Rollback test passed: the previous revision recovered.'
                        } else {
                            int rolloutStatus = bat(
                                returnStatus: true,
                                script: "kubectl rollout status deployment/${env.K8S_DEPLOYMENT} --timeout=120s"
                            )

                            if (rolloutStatus != 0) {
                                echo 'Stable deployment failed. Collecting diagnostics.'

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

                                bat "kubectl rollout status deployment/${env.K8S_DEPLOYMENT} --timeout=120s"

                                error('Stable deployment failed. The previous revision was restored.')
                            }

                            bat "kubectl get deployment ${env.K8S_DEPLOYMENT}"
                            bat 'kubectl get pods'
                            bat "kubectl get service ${env.K8S_SERVICE}"

                            echo 'Stable deployment completed successfully.'
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            bat 'docker rm -f e-waste-smoke >NUL 2>&1 || exit /b 0'
            echo 'Pipeline finished. Review the stage logs and deployment status.'
        }
    }
}
