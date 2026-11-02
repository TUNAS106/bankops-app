pipeline {
    // Dùng node Jenkins hiện có (Built-In Node trong lab).
    agent any
    // Chạy tuần tự, giới hạn thời gian và giữ số lượng report vừa phải.
    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        skipStagesAfterUnstable()
        timestamps()
        timeout(time: 120, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '15', artifactNumToKeepStr: '10'))
    }
    // Lần đầu bỏ chọn publish để kiểm tra các gate trước khi push.
    parameters {
        booleanParam(name: 'PUBLISH_IMAGES', defaultValue: false,
                     description: 'Push all 8 images after every gate passes')
    }
    environment {
        // THAY bằng username/organization Docker Hub thật trước khi chạy.
        DOCKERHUB_NAMESPACE = 'tunas106'
    }
    stages {
        stage('Checkout') {
            steps {
                // Xóa workspace cũ để report lần trước không lẫn vào lần này.
                deleteDir()
                // Lấy repo và branch đã cấu hình trong Pipeline from SCM.
                checkout scm
                script {
                    env.SOURCE_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    // Cùng một tag được dùng cho toàn bộ tám image.
                    env.IMAGE_TAG = "sha-${env.SOURCE_SHA.take(12)}-b${env.BUILD_NUMBER}"
                }
                sh '''
                    set -eu
                    test "$DOCKERHUB_NAMESPACE" != YOUR_DOCKERHUB_NAMESPACE
                    mkdir -p reports
                    git rev-parse HEAD > reports/source-sha.txt
                    printf '%s\n' "$IMAGE_TAG" > reports/image-tag.txt
                    git status --short
                    whoami
                    docker version
                '''
            }
        }
        stage('Lint and unit tests') {
            steps {
                sh 'bash scripts/ci/quality.sh'
            }
            post {
                always {
                    // Test thất bại vẫn thu XML; lint fail sớm có thể chưa có XML.
                    junit testResults: 'src/accounts/*/reports/junit.xml,src/ledger/*/target/surefire-reports/TEST-*.xml',
                          allowEmptyResults: true
                }
            }
        }
        stage('Build 8 images') {
            steps { sh 'bash scripts/ci/build.sh' }
        }
        stage('Scan 8 images') {
            steps { sh 'bash scripts/ci/scan.sh' }
        }
        stage('Publish Docker Hub') {
            when { expression { return params.PUBLISH_IMAGES } }
            steps {
                // Chỉ cấp credential trong bước push; shell đọc token từ biến môi trường.
                withCredentials([usernamePassword(credentialsId: 'dockerhub-bankops',
                                 usernameVariable: 'DH_USER', passwordVariable: 'DH_TOKEN')]) {
                    sh '''
                        set +x
                        bash scripts/ci/publish.sh
                    '''
                }
            }
        }
    }
    // Thu report và cleanup cả khi một stage trước đó thất bại.
    post {
        always {
            script {
                if (fileExists('scripts/ci/cleanup.sh')) {
                    int cleanupStatus = sh(script: 'bash scripts/ci/cleanup.sh', returnStatus: true)
                    if (cleanupStatus != 0) {
                        unstable('Cleanup incomplete: inspect CI image tags and temporary Docker config')
                    }
                }
            }
            archiveArtifacts artifacts: 'reports/**,src/accounts/*/reports/*.xml,src/ledger/*/target/surefire-reports/*.xml,src/ledger/*/target/site/jacoco/**',
                             allowEmptyArchive: true
        }
        success {
            echo 'All enabled stages passed. Check artifacts for publish status; RKE2 is unchanged.'
        }
    }
}
