#!/bin/bash
ELB_Name=<ELB_NAME>
Region=<AWS_REGION>
AUTO_SCALING_Group=<AUTOSCALING GROUP>
Deployment_status=1 #deployment unsuccessful
old_commit_id=`cat ~/deployments/CURRENT_REVISION`
	old_min_size=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $AUTO_SCALING_Group --query 'AutoScalingGroups[].MinSize[]' --output text`
	old_max_size=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $AUTO_SCALING_Group --query 'AutoScalingGroups[].MaxSize[]' --output text`
	old_desired_capacity=`aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $AUTO_SCALING_Group --query 'AutoScalingGroups[].DesiredCapacity[]' --output text`
	echo "===============RESTRICTING AUTOSCALING TO AVOID ANY NEW CHANGES IN MIN/MAX/DESIRED CONFIGURATIONS, PLEASE WAIT==============="
	sleep 10
	aws autoscaling update-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_Group --min-size $old_desired_capacity --output text
	aws autoscaling update-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_Group --max-size $old_desired_capacity --output text
	sleep 10


	Instance_IDs=($(aws elb describe-load-balancers --load-balancer-names $ELB_Name --query 'LoadBalancerDescriptions[].Instances[].InstanceId'  --output text))

	for i in "${Instance_IDs[@]}"
	do
		private_ip=`aws ec2 describe-instances --instance-ids $i --query 'Reservations[].Instances[].PrivateIpAddress' --output text`
		IPs=$IPs,"$private_ip"
	done

	IP_format=`echo $IPs | sed 's/,/"/'|sed 's/,/","/g' | sed 's/$/"/'`
	echo "Appending this format to Capistrano's deploy.rb under :role tag:"$IP_format
	echo "present directory :-`pwd`"
	mail_IP_format=`echo "$IPs"|sed  's/,//'`
	sed -i "/role\ \:app/d" ~/deployments/benchpress-server/config/deploy/aws.rb #append IP under roles tag
	sed -i '/######/a role\ :app,'$IP_format'' ~/deployments/benchpress-server/config/deploy/aws.rb #append IP under roles tag
	cd ~/deployments/benchpress-server/config/deploy/aws.rb
	cap aws deploy
	if [ $? == 0 ]
        then
		echo "Deployment successful"
		Deployment_status=0;
		echo "Fetching latest git commit from the server with private IP :"$private_ip
	        commit_id=`ssh -oStrictHostKeyChecking=no "$private_ip" cat /var/www/html/REVISION` #TODO: Add REVISION file to /var/www/html/REVISION
		echo "=========UPDATING CURRENT_REVISION FILE WITH NEW COMMIT ID=========="
	        echo "$commit_id" > ~/deployments/CURRENT_REVISION
			if [ $commit_id = $old_commit_id ]
			then
				echo "!!!!!!!!!!!!!!same commit deployed again,not updating PREVIOUS_REVISION FILE!!!!!!!!!! " ;
		 	else
				echo "=========NEW COMMIT DETECTED...UPDATING PREVIOUS_REVISION FILE WITH PREVIOUS COMMIT ID=========="
				echo "$old_commit_id" > ~/deployments/PREVIOUS_REVISION
			fi
        	else
		echo "Deployment failed"
		fi
	#Mail Acknowledgement of the deployment status
		if [ $Deployment_status == 0 ]
		then
        	( echo "Subject: Deployemnt Successful on the All the Servers" ; echo "The new Git commit ID $commit_id has been successfully deployed  on all the servers under ELB.The IP of the servers are $mail_IP_format" ) | /usr/sbin/sendmail -F Deployment-Alert skylar@10000ft.com
        	else
        	( echo "Subject: Deployemnt failed on the servers" ; echo "Deployment failed on the servers--Rollbacking to the previous commit ID - $old_commit_id" ) | /usr/sbin/sendmail -F Deployment-Alert skylar@10000ft.com
		echo "CURRENT DIRECTORY:- `pwd`"
		cap aws deploy:rollback
		echo "!!!!!!!!!!!!!!!!!!!ROLLBACK DONE!!!!!!!!!!!!!!!!!!!"
		fi
echo "===============SETTING AUTOSCALING VARIABLES (MIN/MAX/DESIRED CONFIGURATIONS) TO THEIR PREVIOUS VALUE, PLEASE WAIT==============="
	sleep 10
        aws autoscaling update-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_Group --min-size $old_min_size --output text
        aws autoscaling update-auto-scaling-group --auto-scaling-group-name $AUTO_SCALING_Group --max-size $old_max_size --output text
	if [ $? == 0 ]
	then
		echo "AUTOSCALING CONFIGURATIONS REVERTED SUCCESSFULLY"
	else
		echo "AUTOSCALING CONFIGURATIONS FAILED TO REVERT, PLEASE CHECK YOUR CREDENTIALS"
	fi
	cd ~
