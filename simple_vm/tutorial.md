# Lab - Simple VM

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

A l'aide du module Terraform CEINS, vous allez créer une instance GCE simple, prête à l'emploi et conforme aux standards U TECH.

## Prérequis

1.  Un projet GCP.
2.  Les permissions nécessaires pour créer des instances Google Compute Engine.

## Sélection du projet GCP

<walkthrough-project-setup></walkthrough-project-setup>

Puis définisser votre ID de projet dans une variable d'environnement pour faciliter les prochaines étapes :

```bash
export PROJECT_ID=$(gcloud config get-value project)
echo "Projet actuel : $PROJECT_ID"
```

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

Nous allons créer un fichier `main.tf` qui appelle le module pour créer une VM simple.

1.  Créez un nouveau répertoire pour votre projet de test et déplacez-vous dedans :

    ```bash
    mkdir -p ~/simple-vm
    cd ~/simple-vm
    ```

2.  Créez le fichier `main.tf`.

    <walkthrough-editor-open-file filePath="simple-vm/main.tf">Ouvrir l'éditeur</walkthrough-editor-open-file>

    Copiez le contenu suivant dans le fichier `main.tf` :

    ```hcl
    variable "project_id" {}

    module "simple_vm" {
        source = "github.com/ugieiris/tf-module-gcp-ceins?ref=v21.0.0"

        project_id = var.project_id

        instance_base_name = "simplevm"
        instance_type      = "n2-custom-2-4096"
        description        = "Simple VM"
        instance_profile   = "test"
        os_image_family    = "iaas-rhel-9"

        metadata = {
            iaas-setup-env = "s"
        }
    }
    ```

## Initialisation de Terraform

Initialisez Terraform pour télécharger les modules et les providers nécessaires :

```bash
terraform init
```

## Planification du déploiement

Vérifiez les ressources qui seront créées. Cette étape permet de valider la configuration avant d'appliquer les changements :

```bash
terraform plan -var="project_id=$PROJECT_ID"
```

<walkthrough-spotlight-pointer target="console-output">Vérifiez la sortie pour voir les ressources à créer (Plan: X to add)</walkthrough-spotlight-pointer>

## Création des ressources

Lancez la création des ressources après confirmation :

```bash
terraform apply -var="project_id=$PROJECT_ID"
```

## Connexion à l'instance GCE

Une fois le déploiement terminé, vous pouvez récupérer le nom et la zone de votre instance via les commandes :

```bash
gcloud compute instances list --filter="name:simplevm*" --project=$PROJECT_ID
```

et vous y connecter avec la commande :

```bash
gcloud compute ssh "nom de votre instance" --zone="zone de l'instance"
```

## Nettoyage

Pour éviter des frais inutiles, supprimez les ressources créées une fois le tutoriel terminé.

```bash
terraform destroy -var="project_id=$PROJECT_ID" -auto-approve
```

## Conclusion

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Félicitations !  En quelques minutes, vous avez créé une instance GCE et avez pu vous y connecter.

Pour aller plus loin :
*   Consultez la [documentation complète du module](https://github.com/ugieiris/tf-module-gcp-ceins).
