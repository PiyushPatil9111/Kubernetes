#script to automate the process of creating the AWS ES cluster

eksctl create cluster --name=my-eks-cluster --region=ap-south-1 --zones=ap-south-1a,ap-south-1b --without-nodegroup --node-private-networking
eksctl utils associate-iam-oidc-provider --region ap-south-1 --cluster my-eks-cluster --approve
cd /d/Kubernetes/
echo "created cluster and associated OIDC"
#checking if the Keypair already exists.
key_list=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text)
echo "Keys available are: $key_list"
if [[ "$key_list" == *"kube-demo"* ]];
then
	echo "The key kube-demo	 is already present"
else
	aws ec2 create-key-pair --key-name kube-demo --query 'KeyMaterial' --output text > MyKeyPair_kube-demo.pem
fi
eksctl create nodegroup --cluster=my-eks-cluster \
                       --region=ap-south-1 \
                       --name=eksdemo1-ng-private1 \
                       --node-type=t3a.medium \
                       --nodes=2 \
                       --nodes-min=2 \
                       --nodes-max=2 \
                       --node-volume-size=10 \
                       --ssh-access \
                       --ssh-public-key=kube-demo \
                       --managed \
                       --asg-access \
                       --external-dns-access \
                       --full-ecr-access \
                       --appmesh-access \
                       --alb-ingress-access \
                       --node-private-networking

echo "Node group created "
#creating New Security grp for eks cluster and allowing all ports and ips inbpund then attaching it to the cluster.

Securitygp_id=$(aws eks describe-cluster --name my-eks-cluster --query "cluster.resourcesVpcConfig.securityGroupIds[0]" --output text)
echo "The security grpid is : $Securitygp_id"
aws ec2 authorize-security-group-ingress --group-id $Securitygp_id --protocol all --port all --cidr 0.0.0.0/0

#Downloading the iam policy doc for ALB controller policy and creating the policy.
#curl -o iam_policy_latest.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

curl -O iam_policy_latest.json  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy_latest.json

iam_policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)
echo "The IAM policy ar is $iam_policy_arn"

#creating the IAM service account and attaching the IAM policy we just created.
eksctl create iamserviceaccount --cluster=my-eks-cluster --namespace=kube-system --name=aws-load-balancer-controller --attach-policy-arn $iam_policy_arn --override-existing-serviceaccounts --approve
echo 'service account created'
# TO Confirm if the Service account has been created or not.
eksctl get iamserviceaccount --cluster=my-eks-cluster --namespace=kube-system --name=aws-load-balancer-controller

#installing certificate manager before applying the alb controller manifest so it will come up healthy.
#kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.6.1/cert-manager.yaml
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.5/cert-manager.yaml
echo "The certificate manager created"
kubectl get crds | grep 'cert-manager.io'

# Creating the load balancer controller from alb-ingress-controller.yaml from github
echo "applying the alb-ingress-controller.yaml manifest"

curl -Lo v2_7_2_full.yaml https://github.com/kubernetes-sigs/aws-load-balancer-controller/releases/download/v2.7.2/v2_7_2_full.yaml
#Removing the lines 612 to 620 from manifest file create a new iamservice account
sed -i.bak -e '612,620d' ./v2_7_2_full.yaml

#Replacing the cluster name with my-eks-cluster
sed -i.bak -e 's|your-cluster-name|my-eks-cluster|' ./v2_7_2_full.yaml

kubectl apply -f v2_7_2_full.yaml
echo "The ingress controller is as follows:"
kubectl get deploy aws-load-balancer-controller -n kube-system

echo "Creating Ingress Class"
kubectl apply -f /d/Kubernetes/ALB-INGRESS/Ingress_class.yaml
kubectl get ingressclass

echo "creating the deployment and nodeport service for the nginx application"
kubectl apply -f /d/Kubernetes/ALB-INGRESS/app_deployment.yaml
kubectl apply -f /d/Kubernetes/ALB-INGRESS/app_nodeport_service.yaml

echo "end of script"
