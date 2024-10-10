
# Enable WinRM service
Write-Output "Enabling WinRM service..."
winrm quickconfig -q

# Set WinRM to start automatically
Write-Output "Setting WinRM service to start automatically..."
Set-Service -Name "WinRM" -StartupType Automatic

# Allow unencrypted traffic (for internal/trusted networks)
Write-Output "Configuring WinRM to allow unencrypted traffic..."
winrm set winrm/config/service '@{AllowUnencrypted="true"}'

# Allow basic authentication
Write-Output "Enabling Basic Authentication for WinRM..."
winrm set winrm/config/service/auth '@{Basic="true"}'

# Set up firewall rules for WinRM HTTP
Write-Output "Configuring firewall rule for WinRM over HTTP..."
New-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -DisplayName "WinRM over HTTP" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5985

# Configure HTTPS Listener
Write-Output "Setting up WinRM HTTPS listener..."

# Check if an HTTPS listener already exists
$existingHttpsListener = winrm enumerate winrm/config/listener | Select-String -Pattern "Transport=HTTPS"
if (-not $existingHttpsListener) {
    # Generate a self-signed certificate if none is available (for testing purposes)
    $cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation Cert:\LocalMachine\My
    $certThumbprint = $cert.Thumbprint

    # Create an HTTPS listener on port 5986 using the certificate
    winrm create winrm/config/listener?Address=*+Transport=HTTPS '@{Hostname="localhost"; CertificateThumbprint="' + $certThumbprint + '"}'

    Write-Output "HTTPS listener created successfully."
} else {
    Write-Output "HTTPS listener already exists."
}

# Set up firewall rule for WinRM HTTPS
Write-Output "Configuring firewall rule for WinRM over HTTPS..."
New-NetFirewallRule -Name "WinRM-HTTPS-In-TCP" -DisplayName "WinRM over HTTPS" -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986

Write-Output "WinRM configuration for HTTP and HTTPS completed."

