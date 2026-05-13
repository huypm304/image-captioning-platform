pipeline {
  agent none

  parameters {
    string(
      name: 'AGENT_LABEL',
      defaultValue: 'laptop',
      description: 'Agent label for checkout / test / build / GitOps (kubectl, docker, AWS CLI on agent).'
    )
    string(
      name: 'GITOPS_CREDENTIALS_ID',
      defaultValue: 'gitops-git-pat',
      description: 'Jenkins "Username with password" credential id for Git HTTPS push in update-gitops (username = GitHub user, password = PAT with repo scope). Create in Manage Jenkins → Credentials, or change this to your existing id.'
    )
    string(
      name: 'GITOPS_PUSH_BRANCH',
      defaultValue: '',
      description: 'Branch name to push update-gitops (e.g. feature/test). Use when the job uses detached HEAD and auto-detect fails. Leave empty to use BRANCH_NAME / GIT_BRANCH / CHANGE_BRANCH.'
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
              env.GITOPS_PUSH_BRANCH = (params.GITOPS_PUSH_BRANCH ?: '').trim()

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
                  credentialsId: params.GITOPS_CREDENTIALS_ID,
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
