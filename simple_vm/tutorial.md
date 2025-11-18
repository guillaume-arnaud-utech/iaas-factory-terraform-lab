# Lab - Simple VM

<walkthrough-project-id/>

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

## Description

A l'aide du module Terraform CEINS, vous allez créer une instance GCE simple, prête à l'emploi et conforme aux standards U TECH.

> **Avant de commencer, assurez-vous d'avoir sélectionner le projet GCP à utiliser via le menu déroulant.**

## Création d'un token GitHub

> **Cette étape n'est nécessaire que dans le cadre de ce lab.**

Le clone du dépot Git contenant le module CEINS via Terraform nécessite un token GitHub (PAT), l'authentification par mot de passe étant désactivée.

Pour créer ce token, rendez-vous sur la page :

[https://github.com/settings/tokens/new](https://github.com/settings/tokens/new)

Les informations suivantes vous seront demandées :

> **Token name** : `iaas-factory-terraform-lab`

> **Select scopes** : `repo`

Veillez à bien noter le token pour la suite de ce lab.

> **Avant de passer à l'étape suivante, lancer la commande ci-dessous pour mettre en cache le token GitHub afin de ne pas devoir le saisir à chaque utilisation :**

```bash
git config --global credential.helper store
```

## Utilisation du module Terraform CEINS

Le fichier `main.tf` contient un exemple de code Terraform prête à l'emploi après avoir modifié l'attribut `project_id` pour qu'il corresponde au projet GCP précédemment sélectionné.

Exemple :

```hcl
project_id = "tec-iaasint-s-ws49"
```

Ensuite, initialisez votre environnement Terraform avec la commande :

```bash
terraform init
```

> **Lorsque Terraform vous demande de vous authentifier, utilisez le token GitHub précédemment créé à la place du mot de passe.**

Planifiez votre déploiement avec la commande :

```bash
terraform plan
```

Et enfin, déploiez votre instance GCE avec la commande :

```bash
terraform apply
```

## Connexion à l'instance GCE

Une fois le déploiement terminé, vous pouvez récupérer le nom et la zone de votre instance via les commandes :

```bash
gcloud config set project 'id du projet GCP sélectionné'
gcloud compute instances list
```

et vous y connecter avec la commande :

```bash
gcloud compute ssh 'nom de votre instance' --zone='zone de l'instance'
```

## Nettoyage

Vous pouvez nettoyer votre environnement en supprimant l'instance GCE avec la commande :

```bash
terraform destroy
```

## Conclusion

En quelques minutes, vous avez créé une instance GCE et avez pu vous y connecter.

Félicitations, vous avez terminé ce lab !
