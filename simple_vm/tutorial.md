# Lab - Simple VM

<walkthrough-project-id/>

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

## Description

A l'aide du module CEINS, vous allez créer une instance GCE simple, prête à l'emploi et conforme aux standards U TECH.

## Création d'un token GitHub

Le clone du dépot Git contenant le module CEINS via Terraform nécessite un token GitHub (PAT), l'authentification par mot de passe étant désactivée.

Pour créer ce token, rendez-vous sur la page https://github.com/settings/personal-access-tokens/new

Les informations suivantes vous seront demandées :

Token name : `iaas-factory-terraform-lab`
Repository access : `All repositories`

Veillez à bien noter le token pour la suite de ce lab.

## Utilisation du module Terraform CEINS

Sélectionnez le projet GCP dans lequel vous allez créer votre instance GCE via le bouton "Select a project" ci-dessus.

Le fichier `main.tf` contient un exemple de code Terraform prête à l'emploi.

Initialisez votre environnement Terraform avec la commande suivante :

```bash
terraform init
```

Planifiez votre déploiement avec la commande suivante :

```bash
terraform plan
```

Et enfin, déploiez votre instance GCE avec la commande suivante :

```bash
terraform apply
```
