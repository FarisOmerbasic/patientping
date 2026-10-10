# PatientPing

A hands-on DevOps project: an appointment reminder service and the infrastructure around it, built up step by step from a laptop to AWS. Built by Faris Omerbasic while learning DevOps and SRE.

Clinics store patients and appointments through a Go API backed by SQL Server, and a worker sends a reminder before each appointment. The app is kept small on purpose. The work is in everything around it: containers, CI/CD, AWS, infrastructure as code and monitoring, with Kubernetes after that.

## Where it's heading

| Phase | What gets built | Release |
|---|---|---|
| 1 | Go API and worker, Docker and Compose, CI/CD with GitHub Actions, deployment to AWS EC2 through SSM, Terraform, Prometheus, Grafana and CloudWatch alerting | `v1.0.0` |
| 2 | Migration from EC2 to Kubernetes (EKS), Helm, GitOps with Argo CD, SLOs, upgrade exercises | `v2.0.0` |
| 3 | Ansible, Azure, Windows Server, SQL Server operations, SRE practices | `v3.0.0` |
