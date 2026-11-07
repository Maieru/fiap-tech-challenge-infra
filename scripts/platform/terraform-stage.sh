#!/usr/bin/env bash
set -euo pipefail
case "$STAGE:$OPERATION" in
  aws-resources:apply|aws-resources:destroy|kubernetes-addons:apply|kubernetes-addons:destroy|kubernetes-configs:apply|kubernetes-configs:destroy|messaging:apply|messaging:destroy|api-gateway:apply|api-gateway:destroy|database:apply|database:destroy) ;;
  *) echo 'Estagio/operacao nao permitido.' >&2; exit 1 ;;
esac
[[ "$SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]] || exit 1
[[ "$(git rev-parse HEAD)" == "$SOURCE_SHA" ]] || { echo 'Checkout divergente do SHA selecionado.' >&2; exit 1; }
export TF_IN_AUTOMATION=true
folder="infra/$STAGE"
terraform -chdir="$folder" init -input=false
terraform -chdir="$folder" fmt -check -recursive
terraform -chdir="$folder" validate -no-color
case "$STAGE" in
  kubernetes-addons|kubernetes-configs) terraform -chdir="$folder" test -no-color ;;
esac
if [[ "$OPERATION" == destroy ]]; then
  if ! terraform -chdir="$folder" state list >"$RUNNER_TEMP/state-resources" 2>"$RUNNER_TEMP/state-error"; then
    if ! grep -q 'No state file was found' "$RUNNER_TEMP/state-error"; then cat "$RUNNER_TEMP/state-error" >&2; exit 1; fi
  fi
  if [[ ! -s "$RUNNER_TEMP/state-resources" ]]; then
    if [[ "$STAGE" == database ]]; then node scripts/platform/verify-databases-deleted.mjs; fi
    node scripts/platform/wait-secret-deletion.mjs
    echo "$STAGE ja esta vazio." >> "$GITHUB_STEP_SUMMARY"
    exit 0
  fi
  export TF_VAR_new_relic_license_key=destroy-unused
else
  if [[ "$STAGE" == aws-resources ]]; then
    count=$(aws eks describe-addon-versions --addon-name aws-ebs-csi-driver --kubernetes-version 1.36 --query 'length(addons)' --output text)
    [[ "$count" -gt 0 ]] || { echo 'EKS 1.36/EBS CSI indisponivel na regiao.' >&2; exit 1; }
  elif [[ "$STAGE" == database ]]; then
    count=$(aws rds describe-orderable-db-instance-options --engine postgres --engine-version 18.3 --db-instance-class db.t4g.micro --query 'length(OrderableDBInstanceOptions)' --output text)
    [[ "$count" -gt 0 ]] || { echo 'PostgreSQL 18.3/db.t4g.micro indisponivel.' >&2; exit 1; }
  elif [[ "$STAGE" == kubernetes-addons ]]; then
    [[ -n "$TF_VAR_new_relic_license_key" ]] || { echo 'Configure NEW_RELIC_LICENSE_KEY.' >&2; exit 1; }
  fi
fi
if [[ "$STAGE" == api-gateway ]]; then
  if [[ "$OPERATION" == destroy ]]; then
    TF_VAR_internal_alb_listener_arn=$(terraform -chdir="$folder" output -raw internal_alb_listener_arn)
  else
    alb=$(aws elbv2 describe-load-balancers --names fiap-internal-edge --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    aws elbv2 wait load-balancer-available --load-balancer-arns "$alb"
    TF_VAR_internal_alb_listener_arn=$(aws elbv2 describe-listeners --load-balancer-arn "$alb" --query 'Listeners[?Port==`80`].ListenerArn | [0]' --output text)
  fi
  [[ "$TF_VAR_internal_alb_listener_arn" == arn:aws:elasticloadbalancing:* ]] || exit 1
  export TF_VAR_internal_alb_listener_arn
fi
volumes=()
if [[ "$STAGE:$OPERATION" == messaging:destroy ]]; then
  bash scripts/platform/install-kubectl.sh
  for namespace in fiap-messaging fiap-mongodb; do
    claims=$(kubectl -n "$namespace" get pvc -o jsonpath='{range .items[*]}{.spec.volumeName}{"\n"}{end}')
    while IFS= read -r pv; do
      [[ -n "$pv" ]] || continue
      volumes+=("$(kubectl get pv "$pv" -o jsonpath='{.spec.csi.volumeHandle}')")
    done <<< "$claims"
  done
fi
plan="$RUNNER_TEMP/$STAGE.tfplan"
trap 'rm -f "$plan"' EXIT
args=()
if [[ "$OPERATION" == destroy ]]; then args+=(-destroy); fi
terraform -chdir="$folder" plan "${args[@]}" -input=false -lock-timeout=5m -out="$plan"
terraform -chdir="$folder" apply -input=false -lock-timeout=5m -auto-approve "$plan"
if [[ "$STAGE:$OPERATION" == messaging:destroy ]]; then
  for volume in "${volumes[@]}"; do aws ec2 wait volume-deleted --volume-ids "$volume"; done
elif [[ "$STAGE:$OPERATION" == database:destroy ]]; then
  node scripts/platform/verify-databases-deleted.mjs
fi
if [[ "$OPERATION" == destroy ]]; then node scripts/platform/wait-secret-deletion.mjs; fi
if [[ "$OPERATION" == apply ]]; then
  case "$STAGE" in
    api-gateway) echo "api_endpoint=$(terraform -chdir="$folder" output -raw api_endpoint)" >> "$GITHUB_OUTPUT" ;;
    messaging)
      bash scripts/platform/install-kubectl.sh
      kubectl -n fiap-mongodb wait externalsecret/mongodb-server --for=condition=Ready --timeout=180s
      kubectl -n fiap-mongodb rollout status statefulset/mongodb --timeout=10m
      kubectl -n fiap-messaging rollout status statefulset/kafka --timeout=10m
      kubectl -n fiap-messaging wait job/kafka-topics --for=condition=complete --timeout=10m
      echo "bootstrap_servers=$(terraform -chdir="$folder" output -raw bootstrap_servers)" >> "$GITHUB_OUTPUT"
      ;;
  esac
fi
