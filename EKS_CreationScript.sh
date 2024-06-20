#script to automate the process of creating the AWS ES cluster

eksctl create cluster --name=my-eks-cluster --region=ap-south-1 --zones=ap-south-1a,ap-south-1b --without-nodegroup --node-private-networking
eksctl utils associate-iam-oidc-provider --region ap-south-1 --cluster my-eks-cluster --approve
cd D:\Kubernetes

#checking if the Keypair already exists.
key_list=$(aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output text)
echo "Keys available are: $key_list"
echo "keys avaialble are : $key_list"
if [[ "$key_list" == *"kube-demo"* ]];
then
	echo "The key kube-demo	 is already present"
else
	aws ec2 create-key-pair --key-name kube-demo --query 'KeyMaterial' --output text > MyKeyPair_kube-demo.pem
fi
eksctl create nodegroup --cluster=my-eks-cluster \
                       --region=ap-south-1 \
                       --name=eksdemo1-ng-public1 \
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

#creating New Security grp for eks cluster and allowing all ports and ips inbpund then attaching it to the cluster.

Securitygp_id=$(aws eks describe-cluster --name my-eks-cluster --query "cluster.resourcesVpcConfig.securityGroupIds[0]" --output text)
echo "The security grpid is : $Securitygp_id"
aws ec2 authorize-security-group-ingress --group-id $Securitygp_id --protocol all --port all --cidr 0.0.0.0/0

#Downloading the iam policy doc for ALB controller policy and creating the policy.
curl -o iam_policy_latest.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy_latest.json

iam_policy_arn=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)
echo "The IAM policy ar is $iam_policy_arn"

#creating the IAM service account and attaching the IAM policy we just created.
eksctl create iamserviceaccount --cluster=my-eks-cluster --namespace=kube-system --name=aws-load-balancer-controller --attach-policy-arn $iam_policy_arn --override-existing-serviceaccounts --approve

# TO Confirm if the Service account has been created or not.
eksctl get sa aws-load-balancer-controller -n kube-system

# Creating the load balancer controller from alb-ingress-controller.yaml from github
echo "applying the alb-ingress-controller.yaml manifest"
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/v2_2_0_full.yaml
echo "The ingress controller is as follows:"
kubectl get deploy aws-load-balancer-controller -n kube-system
