#!/bin/bash

set +e
set +x

. ./config.sh

setup_istio()
{
    # Cluster A
    # Install Istio
    kubectl apply -f istio-1.0.0/istio-demo.yaml --context=$CLUSTER_A
    # Install CoreDNS
    kubectl apply -f cluster-admin/coredns.yaml --context=$CLUSTER_A
    
    # Cluster B
    # Install Istio
    kubectl apply -f istio-1.0.0/istio-demo.yaml --context=$CLUSTER_B
    # Install CoreDNS
    kubectl apply -f cluster-admin/coredns.yaml --context=$CLUSTER_B
}

configure_cross_cluster()
{
    # Cluster A
    CORE_DNS_IP=`kubectl get svc core-dns -n istio-system -o jsonpath='{.spec.clusterIP}' --context=$CLUSTER_A`
    INGRESS_B_IP=`kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.clusterIP}' --context=$CLUSTER_B`
    INGRESS_B_PORT=`kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http2")].port}' --context=$CLUSTER_B`
	sed -e "s/INGRESS_IP_ADDRESS/$INGRESS_B_IP/g" \
	    -e "s/INGRESS_PORT/$INGRESS_B_PORT/g" \
		-e "s/CORE_DNS_IP/$CORE_DNS_IP/g" \
		cluster-admin/cluster-a/cross-cluster.yaml | kubectl --context=$CLUSTER_A apply -f -

    # Cluster B
    CORE_DNS_IP=`kubectl get svc core-dns -n istio-system -o jsonpath='{.spec.clusterIP}' --context=$CLUSTER_B`
    INGRESS_A_IP=`kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[*].ip}' --context=$CLUSTER_A`
	INGRESS_A_PORT=80
	sed -e "s/INGRESS_IP_ADDRESS/$INGRESS_A_IP/g" \
	    -e "s/INGRESS_PORT/$INGRESS_A_PORT/g" \
		-e "s/CORE_DNS_IP/$CORE_DNS_IP/g" \
		cluster-admin/cluster-b/cross-cluster.yaml | kubectl  --context=$CLUSTER_B apply -f -
}

install_app()
{
    echo "Install App.."

    for yaml in app/cluster-a/*.yaml
    do
        kubectl apply --context=$CLUSTER_A -f <(istioctl kube-inject -f $yaml)
    done

    for yaml in app/cluster-b/*.yaml
    do
        kubectl apply --context=$CLUSTER_B -f <(istioctl kube-inject --context $CLUSTER_B \
                -f <(sed -e "s/__TONE_ANALYZER_USERNAME__/$TONE_ANALYZER_USERNAME/g" \
                -e "s/__TONE_ANALYZER_PASSWORD__/$TONE_ANALYZER_PASSWORD/g" $yaml))
    done
}

echo "Installing Istio.."
setup_istio

echo
echo "Make sure Istio pods are up and running on both clusters."
echo "Press any key to continue.."
read -n 1 -s

echo "Configuring cross-cluster.."
configure_cross_cluster

echo "Installing the app.."
install_app

echo
echo "Multi-Clustered is ready"
echo "URL: http://$INGRESS_A_IP"
