pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timeout(time: 10, unit: 'MINUTES')
        timestamps()
    }

    stages {
        stage('Checkout source') {
            steps {
                deleteDir()
                checkout scm
            }
        }

        stage('Inspect source') {
            steps {
                sh '''
                    set -eu

                    whoami
                    pwd

                    git rev-parse HEAD
                    git log -1 --format='%h %s'

                    ls src/frontend
                    ls src/accounts
                    ls src/ledger
                '''
            }
        }
    }
}