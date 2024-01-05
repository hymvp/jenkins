/* 首先在项目文件的同目录创建一个tf文件夹，创建demo.tf文件，将本脚本的内容
拷贝至文件，依次执行terrafom init；terraform plan ；terrafrom apply即可
销毁命令：terraform destroy
脚本执行流程：
1、通过fn命令生成function image，推送到镜像仓库。需要根据需求修改yaml中的version
2、生成gateway
3、生成application 、function
4、生成deployment、关联对应function
5、脚本执行完毕后会打印出gateway的url
*/

variable "function_config" {
  description = "Function 配置参数"

  default = {
    project_dir          = "/home/opc/functions/hello"
    images               = "iad.ocir.io/sehubjapacprod/functions/hello/hello-tf:0.0.13"
    compartment_id       = "ocid1.compartment.oc1..aaaaaaaaptdr4gr5mfj72ywuwpegdykybsit2vrk4tkgfuye7rhk7y7efrjq"
    subnet_ids_app       = ["ocid1.subnet.oc1.iad.aaaaaaaait5sepgg4h3wobcvosqmpokoaj4mkvpnnzd2g73bjyvhtoxehv6a"]
    subnet_ids_gateway   = "ocid1.subnet.oc1.iad.aaaaaaaait5sepgg4h3wobcvosqmpokoaj4mkvpnnzd2g73bjyvhtoxehv6a"
    application_name     = "application-demo04"
    function_name        = "function-test"
    deployment_name      = "deployment-test"
    memory_in_mbs        = 128
    api_path_suffix      = "/{name}"
  }
}

# 修改项目文件中的func.yaml中的version，生成function image，推送到镜像仓库
resource "null_resource" "build_and_push_image" {
  provisioner "local-exec" {
    command = <<EOT
      fn build -w ${var.function_config.project_dir} &&
      docker push ${var.function_config.images}
EOT
  }
}

# 创建一个新的application
resource "oci_functions_application" "test_application" {
  compartment_id = var.function_config.compartment_id
  display_name   = var.function_config.application_name
  subnet_ids     = var.function_config.subnet_ids_app
}

# 创建一个新的function
resource "oci_functions_function" "test_function" {
  depends_on     = [null_resource.build_and_push_image]
  application_id = oci_functions_application.test_application.id
  display_name   = var.function_config.function_name
  memory_in_mbs   = var.function_config.memory_in_mbs
  image          = var.function_config.images

  provisioned_concurrency_config {
    strategy = "NONE"
  }
}

# 创建一个新的gateway(也可以修改脚本逻辑，使用已有的gateway)
resource "oci_apigateway_gateway" "test_gateway" {
  compartment_id = var.function_config.compartment_id
  endpoint_type  = "PUBLIC"
  subnet_id      = var.function_config.subnet_ids_gateway
}

# 创建一个新的deployment关联function
resource "oci_apigateway_deployment" "generated_oci_apigateway_deployment" {
  compartment_id = var.function_config.compartment_id
  display_name   = var.function_config.deployment_name
  gateway_id     = oci_apigateway_gateway.test_gateway.id
  path_prefix    = "/get"
  specification {
    logging_policies {
      execution_log {
        log_level = "INFO"
      }
    }
    request_policies {
      mutual_tls {
        is_verified_certificate_required = "false"
      }
    }
    routes {
      backend {
        function_id = oci_functions_function.test_function.id
        type        = "ORACLE_FUNCTIONS_BACKEND"
      }
      logging_policies {
      }
      methods = ["GET"]
      path    = var.function_config.api_path_suffix
    }
  }
}

output "API_GATEWAY_URL" {
  description = "The URL of the OCI API Gateway"
  value       = oci_apigateway_gateway.test_gateway.hostname
}

