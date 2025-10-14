variable "domain_id" {
  type = string
}
variable "user_prefix" {
  type = string
}
variable "execution_role_arn" {
  type = string
}

# -----------------------------------------------------------
# Lifecycle Configuration — clones the GitHub repo's on startup
# -----------------------------------------------------------

resource "aws_sagemaker_studio_lifecycle_config" "clone_repo" {
  studio_lifecycle_config_name     = "clone-repo"
  studio_lifecycle_config_app_type = "JupyterLab"

  studio_lifecycle_config_content = base64encode(<<EOF
  #!/bin/bash
  set -ex

  # =========================================================
  # This lifecycle script runs every time the JupyterLab app
  # starts (unless in Job mode) and does the following:
  # 1. Installs LaTeX packages required for PDF export
  # 2. Clones the GitHub repositories if they don't exist
  # 3. Installs Python dependencies for notebooks
  # 4. Executes 00-start-here.ipynb
  # =========================================================

  # Skip lifecycle config if running in SageMaker Job mode
  if [ ! -z "$SM_JOB_DEF_VERSION" ]; then
    echo "Running in job mode, skipping lifecycle config"
  else
    # -------------------------------
    # Install TeXLive packages
    # -------------------------------
    sudo apt update
    sudo apt install -y texlive-xetex texlive-fonts-recommended texlive-latex-extra

    # -------------------------------
    # Clone repositories if they don't exist
    # -------------------------------
    if [ ! -d "/home/sagemaker-user/sagemaker-made-quick" ]; then
        git clone https://github.com/Jime567/sagemaker-made-quick.git /home/sagemaker-user/sagemaker-made-quick || {
            echo "Error: Failed to clone sagemaker-made-quick"
            exit 0
        }
        echo "Repository successfully cloned: sagemaker-made-quick"
    else
        echo "Repository already exists, skipping clone: sagemaker-made-quick"
    fi

    if [ ! -d "/home/sagemaker-user/amazon-sagemaker-from-idea-to-production" ]; then
        git clone https://github.com/aws-samples/amazon-sagemaker-from-idea-to-production.git /home/sagemaker-user/amazon-sagemaker-from-idea-to-production || {
            echo "Error: Failed to clone amazon-sagemaker-from-idea-to-production"
            exit 0
        }
        echo "Repository successfully cloned: amazon-sagemaker-from-idea-to-production"
    else
        echo "Repository already exists, skipping clone: amazon-sagemaker-from-idea-to-production"
    fi

    # -------------------------------
    # Execute 00-start-here.ipynb notebook
    # -------------------------------
    cd /home/sagemaker-user/amazon-sagemaker-from-idea-to-production/
    if [ -f "00-start-here.ipynb" ]; then
        jupyter nbconvert --to notebook --execute 00-start-here.ipynb --inplace || {
            echo "Warning: Notebook execution failed, continuing..."
        }
        echo "Notebook 00-start-here.ipynb executed."
    else
        echo "Notebook 00-start-here.ipynb not found, skipping execution."
    fi
  fi
  EOF
    )
}

# -----------------------------------------------------------
# User Profile — attaches execution role, attaches lifecycle config
# -----------------------------------------------------------
resource "aws_sagemaker_user_profile" "studio_user" {
  domain_id         = var.domain_id
  user_profile_name = "${var.user_prefix}-${formatdate("YYYYMMDD'T'HHmmss", timestamp())}"

  user_settings {
    execution_role = var.execution_role_arn
    default_landing_uri = "studio::"

    jupyter_lab_app_settings {
      default_resource_spec {
        lifecycle_config_arn = aws_sagemaker_studio_lifecycle_config.clone_repo.arn
      }
      lifecycle_config_arns = [aws_sagemaker_studio_lifecycle_config.clone_repo.arn]
    }
  }
}

output "user_profile_name" {
  value = aws_sagemaker_user_profile.studio_user.user_profile_name
}

output "lifecycle_config_arn" {
  value = aws_sagemaker_studio_lifecycle_config.clone_repo.arn
}
