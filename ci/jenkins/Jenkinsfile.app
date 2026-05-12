pipeline {
  agent none

  parameters {
    string(
      name: 'AGENT_LABEL',
      defaultValue: 'laptop',
      description: 'Parameters — agent label for checkout / test / build / GitOps. AWS + Git use fixed cred IDs: aws-creds-id, gitops-git-pat.'
    )
  }

  environment {
    AWS_REGION         = 'ap-southeast-1'
    AWS_DEFAULT_REGION = 'ap-southeast-1'
    CLUSTER_NAME       = 'image-caption-dev-eks'
    ECR_REPO_BE        = 'image-caption-dev-app'
    ECR_REPO_FE        = 'image-caption-dev-frontend'
  }

  options {
    timestamps()
    disableConcurrentBuilds()
  }

  triggers {
    pollSCM('H/5 * * * *')
  }

  stages {
    stage('CI') {
      steps {
        script {
          def stagesDir = 'ci/jenkins/stages/build_sw'
          withCredentials([[
            $class: 'AmazonWebServicesCredentialsBinding',
            credentialsId: 'aws-creds-id'
          ]]) {
            node(params.AGENT_LABEL) {
              checkout scm

              def accountId = sh(
                returnStdout: true,
                script: 'aws sts get-caller-identity --query Account --output text'
              ).trim()
              env.ECR_REGISTRY = "${accountId}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
              echo "Using ECR_REGISTRY=${env.ECR_REGISTRY}"

              def ciStages = ['checkout', 'backend-test', 'frontend-build', 'security-scan', 'docker-build-push']
              ciStages.each { sName ->
                def cfg = readYaml file: "${stagesDir}/${sName}.yaml"
                stage(cfg.name) {
                  cfg.steps.each { cmd -> sh cmd }
                }
              }

              def cfg = readYaml file: "${stagesDir}/update-gitops.yaml"
              stage(cfg.name) {
                withCredentials([[
                  $class: 'UsernamePasswordMultiBinding',
                  credentialsId: 'gitops-git-pat',
                  usernameVariable: 'GIT_USERNAME',
                  passwordVariable: 'GIT_TOKEN'
                ]]) {
                  cfg.steps.each { cmd -> sh cmd }
                }
              }
            }
          }
        }
      }
    }
  }
}
