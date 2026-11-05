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
    // GitHub plugin nhận push webhook và kiểm tra thay đổi của branch trong job.
    triggers {
        githubPush()
    }
    // Lần đầu bỏ chọn publish để kiểm tra các gate trước khi push.
    parameters {
        booleanParam(name: 'PUBLISH_IMAGES', defaultValue: false,
                     description: 'Push selected images after every gate passes')
        booleanParam(name: 'FORCE_ALL', defaultValue: false,
                     description: 'Build all services regardless of Git changes')
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
                script {
                    def gitInfo = checkout scm
                    // So sánh từ lần THÀNH CÔNG gần nhất để không bỏ thay đổi của build lỗi.
                    env.BASE_COMMIT = gitInfo.GIT_PREVIOUS_SUCCESSFUL_COMMIT ?: ''
                }
                script {
                    env.SOURCE_SHA = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
                    // Các service được chọn dùng tag mới; service không đổi giữ tag cũ khi deploy.
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
        stage('Select changed services') {
            steps {
                // Kiểm tra quy tắc chọn service trước khi dùng nó cho build thật.
                sh 'python3 -m unittest discover -s scripts/ci/tests -v'
                withEnv(["FORCE_ALL=${params.FORCE_ALL}"]) {
                    sh 'python3 scripts/ci/select-services.py'
                }
                script {
                    env.HAS_CHANGES = readFile('reports/selected-services.tsv').trim() ? 'true' : 'false'
                }
            }
        }
        stage('Lint and unit tests') {
            when { expression { env.HAS_CHANGES == 'true' } }
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
        stage('Build selected images') {
            when { expression { env.HAS_CHANGES == 'true' } }
            steps { sh 'bash scripts/ci/build.sh' }
        }
        stage('Scan selected images') {
            when { expression { env.HAS_CHANGES == 'true' } }
            steps { sh 'bash scripts/ci/scan.sh' }
        }
        stage('Publish Docker Hub') {
            when { expression { return params.PUBLISH_IMAGES && env.HAS_CHANGES == 'true' } }
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
