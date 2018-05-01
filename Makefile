build-image:
	carton exec dzil build
	docker build -t workerbase:v1 .
	#docker run --rm -ti workerbase:v1 --queue_url x --region X

deploy-sns-topic:
	aws cloudformation --region eu-west-1 create-stack --stack-name kube-cfn --capabilities CAPABILITY_IAM --template-body file://cfn/snstoqueue.json
	sleep 60;
	aws cloudformation --region eu-west-1 describe-stacks --stack-name kube-cfn --query 'Stacks[0].Outputs'
	
