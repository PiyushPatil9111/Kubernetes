kubectl delete -f Ingress.yaml
kubectl delete -f /d/Kubernetes/ALB-INGRESS/app_nodeport_service.yaml
kubectl delete -f /d/Kubernetes/ALB-INGRESS/app_deployment.yaml

Security_gp=$(aws eks describe-cluster --name my-eks-cluster --query "cluster.resourcesVpcConfig.securityGroupIds[0]" --output text)
aws ec2 revoke-security-group-ingress --group-id $Security_gp --protocol all --port all --cidr 0.0.0.0/0

eksctl delete nodegroup --cluster my-eks-cluster --name eksdemo1-ng-private1

eksctl delete cluster  my-eks-cluster

echo "Node grp and cluster deleted, PLEASE DELETE IAM ROLE for SERVICE ACCT AND ADD A LINE OF CODE HERE"
