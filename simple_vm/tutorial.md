# Lab - Simple VM

<walkthrough-project-id/>

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

## Description

A l'aide du module CEINS, vous allez créer une instance GCE simple, prête à l'emploi et conforme aux standards U TECH.

## Création d'un token GitHub

> Cette étape n'est nécessaire que dans le cadre de ce lab.

Le clone du dépot Git contenant le module CEINS via Terraform nécessite un token GitHub (PAT), l'authentification par mot de passe étant désactivée.

Pour créer ce token, rendez-vous sur la page https://github.com/settings/personal-access-tokens/new

Les informations suivantes vous seront demandées :

Token name : `iaas-factory-terraform-lab`
Repository access : `All repositories`

Veillez à bien noter le token pour la suite de ce lab.

## Sélection du projet GCP

> Cette étape n'est nécessaire que dans le cadre de ce lab.

Sélectionnez le projet GCP dans lequel vous allez créer votre instance GCE via le bouton "Select a project" ci-dessus.

## Utilisation du module Terraform CEINS

Le fichier `main.tf` contient un exemple de code Terraform prête à l'emploi après avoir modifié l'attribut `project_id` pour qu'il corresponde à votre projet GCP.

Exemple :

```hcl
project_id = "tec-iaasint-s-ws49"
```

Ensuite, initialisez votre environnement Terraform avec la commande :

```bash
terraform init
```

Planifiez votre déploiement avec la commande :

```bash
terraform plan
```

Et enfin, déploiez votre instance GCE avec la commande :

```bash
terraform apply
```

## Connexion à l'instance GCE

Une fois le déploiement terminé, vous pouvez accéder à votre instance GCE via la commande :

```bash
gcloud compute ssh 'nom de votre instance'
```

## Nettoyage

Vous pouvez nettoyer votre environnement en supprimant l'instance GCE avec la commande :

```bash
terraform destroy
```
