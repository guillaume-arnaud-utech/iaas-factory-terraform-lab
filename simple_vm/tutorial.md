# Lab - Simple VM

<walkthrough-tutorial-duration duration="30"></walkthrough-tutorial-duration>

A l'aide du module Terraform CEINS, vous allez créer une instance GCE simple, prête à l'emploi et conforme aux standards U TECH.

## Préparation de l'environnement

<walkthrough-project-setup></walkthrough-project-setup>

Avant de commencer, il est nécessaire d'éxecuter le script `bootstrap.sh` pour le bon déroulement de ce lab :

```bash
/bin/bash bootstrap.sh
```

## Utilisation du module Terraform CEINS

Vous allez écrire le code qui appelle le module pour créer une VM simple.

1. Créez un nouveau répertoire de travail contenant un fichier `main.tf` :

```bash
mkdir -p ./simple-vm
cd ./simple-vm
touch main.tf
```

1. Ouvrez le fichier `main.tf`.

<walkthrough-editor-open-file filePath="simple-vm/main.tf">Ouvrir l'éditeur</walkthrough-editor-open-file>

Copiez le contenu suivant dans le fichier `main.tf` :

```hcl
module "simple_vm" {
    source = "github.com/ugieiris/tf-module-gcp-ceins?ref=v22.4.1"

    project_id         = "<walkthrough-project-id/>"
    instance_base_name = "simplevm"
    instance_type      = "n4-highcpu-2"
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
terraform plan
```

<walkthrough-spotlight-pointer target="console-output">Vérifiez la sortie pour voir les ressources à créer (Plan: X to add)</walkthrough-spotlight-pointer>

## Création des ressources

Lancez la création des ressources après confirmation :

```bash
terraform apply
```

## Connexion à l'instance GCE

Une fois le déploiement terminé, vous pouvez récupérer le nom et la zone de votre instance via les commandes :

```bash
gcloud compute instances list --filter="name:simplevm*" --project="<walkthrough-project-id/>"
```

et vous y connecter avec la commande :

```bash
gcloud compute ssh "nom de votre instance" --zone="zone de l'instance" --project="<walkthrough-project-id/>"
```

## Nettoyage

Pour éviter des frais inutiles, supprimez les ressources créées une fois le tutoriel terminé.

```bash
terraform destroy
```

## Conclusion

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Félicitations !  En quelques minutes, vous avez créé une instance GCE et avez pu vous y connecter.

Pour aller plus loin :

* Consultez la [documentation complète du module](https://github.com/ugieiris/tf-module-gcp-ceins).
