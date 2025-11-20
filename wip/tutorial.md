# Déployer une VM avec le module tf-module-gcp-ceins

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

Ce tutoriel vous guide dans l'utilisation du module Terraform `tf-module-gcp-ceins` pour déployer une machine virtuelle sur Google Cloud Platform.

## Prérequis

1.  Un projet Google Cloud sélectionné.
2.  Les permissions nécessaires pour créer des instances Compute Engine.

## Configuration de l'environnement

<walkthrough-project-setup></walkthrough-project-setup>

Commencez par définir votre ID de projet dans une variable d'environnement pour faciliter les commandes suivantes.

```bash
export PROJECT_ID=$(gcloud config get-value project)
echo "Projet actuel : $PROJECT_ID"
```

## Création du fichier de configuration Terraform

Nous allons créer un fichier `main.tf` qui appelle le module pour créer une VM simple.

1.  Créez un nouveau répertoire pour votre projet de test et déplacez-vous dedans :

    ```bash
    mkdir -p ~/mon-test-vm
    cd ~/mon-test-vm
    ```

2.  Créez le fichier `main.tf`.

    <walkthrough-editor-open-file filePath="mon-test-vm/main.tf">Ouvrir l'éditeur</walkthrough-editor-open-file>

    Copiez le contenu suivant dans le fichier `main.tf` :

    ```hcl
    module "simple_vm" {
      # Utilisation de la version v21.0.0 du module
      source = "github.com/ugieiris/tf-module-gcp-ceins?ref=v21.0.0"

      project_id         = var.project_id
      instance_base_name = "tutovm"
      description        = "VM créée via le tutoriel Cloud Shell"

      # Profil de configuration (test, lowcost, normal, highlevel)
      # Le profil 'test' utilise des disques standards et est en mode SPOT (moins cher)
      instance_profile   = "test"

      # Image OS (ex: iris-rhel-8, iris-windows-2022)
      os_image_family    = "iris-rhel-8"

      # Configuration réseau
      region             = "europe-west9"
      # La zone est optionnelle, si omise elle est choisie aléatoirement dans la région
      zone               = "europe-west9-a"

      # Exemple de disque additionnel
      attached_disks = [
        {
          name        = "data"
          device_name = "data"
          size        = 10
          type        = "pd-standard"
          mode        = "READ_WRITE"
        }
      ]
    }

    variable "project_id" {
      description = "ID du projet GCP"
      type        = string
    }

    output "vm_name" {
      value = module.simple_vm.name
    }

    output "vm_internal_ip" {
      value = module.simple_vm.internal_ip
    }
    ```

## Initialisation de Terraform

Initialisez Terraform pour télécharger le module et les providers nécessaires.

```bash
terraform init
```

## Planification du déploiement

Vérifiez les ressources qui seront créées. Cette étape permet de valider la configuration avant d'appliquer les changements.

```bash
terraform plan -var="project_id=$PROJECT_ID"
```

<walkthrough-spotlight-pointer target="console-output">Vérifiez la sortie pour voir les ressources à créer (Plan: X to add)</walkthrough-spotlight-pointer>

## Application du déploiement

Lancez la création de la VM. Confirmez l'action si demandé (ou utilisez `-auto-approve` comme ci-dessous).

```bash
terraform apply -var="project_id=$PROJECT_ID" -auto-approve
```

Une fois terminé, Terraform affichera les outputs, comme le nom de l'instance et son IP interne.

## Vérification

Vous pouvez vérifier que la VM a bien été créée via la commande gcloud :

```bash
gcloud compute instances list --filter="name:tutovm*" --project=$PROJECT_ID
```

## Nettoyage

Pour éviter des frais inutiles, supprimez les ressources créées une fois le tutoriel terminé.

```bash
terraform destroy -var="project_id=$PROJECT_ID" -auto-approve
```

## Conclusion

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Félicitations ! Vous avez appris à utiliser le module `tf-module-gcp-ceins` pour déployer une VM standardisée respectant les normes IRIS.

Pour aller plus loin :
*   Explorez les autres profils (`lowcost`, `normal`, `highlevel`).
*   Consultez la [documentation complète du module](https://github.com/ugieiris/tf-module-gcp-ceins).
