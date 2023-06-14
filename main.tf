# We strongly recommend using the required_providers block to set the
# Azure Provider source and version being used
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Obtain Home IP range from key vault
# Not sure why this isn't able to pull the secret value, using manual input for now
# 
# data "azurerm_key_vault" "scottvault" {
#   name                = "scottvault"
#   resource_group_name = "vault-rg"
# }
# 
# data "azurerm_key_vault_secret" "home-ip" {
#   name         = "home-ip"
#   key_vault_id = data.azurerm_key_vault.scottvault.id
# }


resource "azurerm_resource_group" "tf-demo" {
  name     = "tf-demo"
  location = "East US"
  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_network" "tf-vn" {
  name                = "tf-vn"
  resource_group_name = azurerm_resource_group.tf-demo.name
  location            = azurerm_resource_group.tf-demo.location
  address_space       = ["10.123.0.0/16"]
  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "tf-subnet" {
  name                 = "tf-subnet"
  resource_group_name  = azurerm_resource_group.tf-demo.name
  virtual_network_name = azurerm_virtual_network.tf-vn.name
  address_prefixes     = ["10.123.10.0/24"]
}

resource "azurerm_network_security_group" "tf-nsg" {
  name                = "tf-nsg"
  location            = azurerm_resource_group.tf-demo.location
  resource_group_name = azurerm_resource_group.tf-demo.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "tf-dev-rule" {
  name                        = "tf-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.home-ip
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.tf-demo.name
  network_security_group_name = azurerm_network_security_group.tf-nsg.name
}

resource "azurerm_subnet_network_security_group_association" "tf-sga" {
  subnet_id                 = azurerm_subnet.tf-subnet.id
  network_security_group_id = azurerm_network_security_group.tf-nsg.id
}

resource "azurerm_public_ip" "tf-ip" {
  name                = "tf-ip"
  resource_group_name = azurerm_resource_group.tf-demo.name
  location            = azurerm_resource_group.tf-demo.location
  allocation_method   = "Dynamic"

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_interface" "tf-nic" {
  name                = "tf-nic"
  resource_group_name = azurerm_resource_group.tf-demo.name
  location            = azurerm_resource_group.tf-demo.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.tf-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.tf-ip.id
  }

  tags = {
    environment = "dev"
  }
}

resource "azurerm_virtual_machine" "tf-vm" {
  name                  = "tf-vm"
  resource_group_name   = azurerm_resource_group.tf-demo.name
  location              = azurerm_resource_group.tf-demo.location
  network_interface_ids = [azurerm_network_interface.tf-nic.id]
  vm_size               = "Standard_B1s"


  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "tf-os-disk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "tf-vm"
    admin_username = "scottify"


  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      key_data = file("./tf-demo.pub")
      path     = "/home/scottify/.ssh/authorized_keys"
    }
  }

  tags = {
    environment = "dev"
  }
}