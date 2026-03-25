# Azure AD (Entra ID) SAML SSO Configuration Guide
## Rancher, ArgoCD & Jenkins on Amazon EKS

**Version:** 1.0  
**Date:** March 2026  
**Protocol:** SAML 2.0  
**Identity Provider:** Microsoft Azure AD (Entra ID) — Enterprise Applications / My Apps Portal  
**Deployment:** Amazon EKS (Kubernetes)

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Application 1: Rancher](#application-1-rancher)
4. [Application 2: ArgoCD](#application-2-argocd)
5. [Application 3: Jenkins](#application-3-jenkins)
6. [Quick Reference Summary](#quick-reference-summary)
7. [Troubleshooting](#troubleshooting)
8. [Reference Links](#reference-links)

---

## Overview

This guide covers configuring SAML SSO for three applications running on Amazon EKS, using Azure AD Enterprise Applications as the Identity Provider. Each application gets its own Enterprise Application in Azure so users can access all three from the Microsoft My Apps portal.

### Architecture

```
User → My Apps Portal (myapplications.microsoft.com)
         ↓
Azure AD / Entra ID (SAML Identity Provider)
         ↓
    ├── Rancher   → Built-in ADFS Auth Provider
    ├── ArgoCD    → Dex SAML Connector
    └── Jenkins   → Jenkins SAML Plugin
```

---

## Prerequisites

### Azure AD
- Entra ID tenant with Global Administrator or Application Administrator access
- Users and security groups already created in Azure AD
- Permission to create Enterprise Applications

### EKS / Kubernetes
- EKS cluster with `kubectl` access configured
- Ingress controller (ALB or Nginx) with TLS termination
- All applications accessible over HTTPS (required for SAML)

### Applications
- **Rancher** v2.7+ installed with admin access
- **ArgoCD** v2.0+ with Dex enabled
- **Jenkins** LTS with admin access

### Placeholder URLs (replace with your actual values)

| Placeholder | Example |
|---|---|
| `<RANCHER_URL>` | `rancher.example.com` |
| `<ARGOCD_URL>` | `argocd.example.com` |
| `<JENKINS_URL>` | `jenkins.example.com` |
| `<TENANT_ID>` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |

---

# Application 1: Rancher

Rancher uses its built-in **ADFS auth provider** for SAML integration.

## Step 1: Generate a TLS Certificate for Rancher

Generate a self-signed certificate that Rancher uses to sign SAML requests:

```bash
openssl req -x509 -newkey rsa:2048 \
  -keyout rancher-saml.key -out rancher-saml.cert \
  -days 365 -nodes \
  -subj "/CN=<RANCHER_URL>"
```

Keep `rancher-saml.key` and `rancher-saml.cert` — you will paste their contents into the Rancher UI.

---

## Step 2: Create Azure AD Enterprise Application

### 2.1 Create the Application

1. Go to **Azure Portal → Azure Active Directory → Enterprise Applications**
2. Click **+ New application → Create your own application**
3. Name: `Rancher`
4. Select: **Integrate any other application you don't find in the gallery**
5. Click **Create**

### 2.2 Configure SAML SSO

1. Go to **Single sign-on → SAML**
2. Click **Edit** under **Basic SAML Configuration**
3. Enter:

| Field | Value |
|---|---|
| Identifier (Entity ID) | `https://<RANCHER_URL>/v1-saml/adfs/saml/metadata` |
| Reply URL (ACS URL) | `https://<RANCHER_URL>/v1-saml/adfs/saml/acs` |
| Sign on URL | `https://<RANCHER_URL>` |

4. Click **Save**

### 2.3 Configure Attributes & Claims

Click **Edit** under **User Attributes & Claims** and configure:

**Add new claims:**

| Claim Name | Source Attribute |
|---|---|
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` | `user.displayname` |
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname` | `user.givenname` |
| `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn` | `user.userprincipalname` |

**Add a group claim:**

- Which groups: **Groups assigned to the application**
- Source attribute: **Group ID**
- Customize: **True**
- Name: `http://schemas.xmlsoap.org/claims/Group`
- Namespace: *(leave empty)*

Click **Save**

### 2.4 Download Federation Metadata XML

1. Under **SAML Certificates**, download the **Federation Metadata XML** file
2. Save it locally (e.g., `rancher-metadata.xml`)

### 2.5 Assign Users and Groups

1. Go to **Users and groups → + Add user/group**
2. Select users/groups that should access Rancher
3. Click **Assign**

---

## Step 3: Configure Rancher

### 3.1 Navigate to Auth Provider

1. Log into Rancher as admin
2. Click **☰ → Users & Authentication → Auth Provider**
3. Click **ADFS**

### 3.2 Fill in the Configuration Form

| Field | Value |
|---|---|
| Display Name Field | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` |
| User Name Field | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname` |
| UID Field | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn` |
| Groups Field | `http://schemas.xmlsoap.org/claims/Group` |
| Rancher API Host | `https://<RANCHER_URL>` |
| Private Key | Paste full contents of `rancher-saml.key` |
| Certificate | Paste full contents of `rancher-saml.cert` |
| Metadata XML | Upload the `rancher-metadata.xml` downloaded from Azure |

### 3.3 Restrict Access by Groups (Optional)

1. Scroll to **Site Access**
2. Select **"Restrict access to only Authorized Users and Organizations"**
3. Add authorized groups (select from dropdown) and users (enter exact UPN)
4. Click **Save**

### 3.4 Enable

1. Click **Enable**
2. You will be redirected to Azure AD login
3. Authenticate to validate the configuration

---

# Application 2: ArgoCD

ArgoCD uses **Dex** as an identity broker with a **SAML connector** for Azure AD.

## Step 1: Create Azure AD Enterprise Application

### 1.1 Create the Application

1. Go to **Azure Portal → Azure Active Directory → Enterprise Applications**
2. Click **+ New application → Create your own application**
3. Name: `ArgoCD`
4. Select: **Integrate any other application you don't find in the gallery**
5. Click **Create**

### 1.2 Configure SAML SSO

1. Go to **Single sign-on → SAML**
2. Click **Edit** under **Basic SAML Configuration**
3. Enter:

| Field | Value |
|---|---|
| Identifier (Entity ID) | `https://<ARGOCD_URL>/api/dex/callback` |
| Reply URL (ACS URL) | `https://<ARGOCD_URL>/api/dex/callback` |
| Sign on URL | `https://<ARGOCD_URL>/auth/login` |

4. Click **Save**

### 1.3 Configure Attributes & Claims

Click **Edit** under **User Attributes & Claims**:

**Add new claim:**

| Claim Name | Source Attribute |
|---|---|
| `email` | `user.mail` |

**Add a group claim:**

- Which groups: **Groups assigned to the application**
- Source attribute: **Group ID**
- Customize: **True**
- Name: `Group`
- Namespace: *(leave empty)*
- Emit groups as role claims: **False**

Click **Save**

### 1.4 Download SAML Signing Certificate

1. Under **SAML Certificates**, click **Download** next to **Certificate (Base64)**
2. Save the file (e.g., `ArgoCD.cer`)

### 1.5 Copy Login URL

Under **Set up ArgoCD**, copy the **Login URL**:
- Example: `https://login.microsoftonline.com/<TENANT_ID>/saml2`

### 1.6 Assign Users and Groups

1. Go to **Users and groups → + Add user/group**
2. Select users/groups that should access ArgoCD
3. Click **Assign**

---

## Step 2: Base64-Encode the Certificate

```bash
cat ArgoCD.cer | base64
```

Copy the entire output. This is used as `caData` in the ArgoCD ConfigMap.

---

## Step 3: Configure ArgoCD on EKS

### 3.1 Edit `argocd-cm` ConfigMap

```bash
kubectl -n argocd edit configmap argocd-cm
```

Add/update the `data` section:

```yaml
data:
  url: https://<ARGOCD_URL>
  dex.config: |
    connectors:
    - type: saml
      id: saml
      name: AzureAD
      config:
        entityIssuer: https://<ARGOCD_URL>/api/dex/callback
        ssoURL: https://login.microsoftonline.com/<TENANT_ID>/saml2
        caData: |
          <BASE64_ENCODED_CERTIFICATE>
        redirectURI: https://<ARGOCD_URL>/api/dex/callback
        usernameAttr: email
        emailAttr: email
        groupsAttr: Group
```

Replace:
- `<ARGOCD_URL>` — your ArgoCD URL
- `<TENANT_ID>` — your Azure tenant ID
- `<BASE64_ENCODED_CERTIFICATE>` — output from the `base64` command above

### 3.2 Edit `argocd-rbac-cm` ConfigMap

```bash
kubectl -n argocd edit configmap argocd-rbac-cm
```

Add/update:

```yaml
data:
  policy.default: role:readonly
  scopes: '[groups, email]'
  policy.csv: |
    # Admin role
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow
    p, role:admin, projects, *, *, allow

    # Deployer role
    p, role:deployer, applications, get, */*, allow
    p, role:deployer, applications, sync, */*, allow
    p, role:deployer, applications, list, */*, allow

    # Map Azure AD Group Object IDs to roles
    g, "<ADMIN_GROUP_OBJECT_ID>", role:admin
    g, "<DEPLOYER_GROUP_OBJECT_ID>", role:deployer
```

Replace `<..._GROUP_OBJECT_ID>` with actual Azure AD Group Object IDs.
Find these in: **Azure Portal → Azure AD → Groups → select group → Object ID**

### 3.3 Restart ArgoCD

```bash
kubectl -n argocd rollout restart deployment argocd-server argocd-dex-server
```

### 3.4 Test

1. Open `https://<ARGOCD_URL>`
2. Click **LOG IN VIA AZUREAD**
3. Authenticate with Azure AD credentials
4. Verify access and group memberships under **User Info**

---

## ArgoCD via Helm (Alternative)

If using Helm, add to `values.yaml`:

```yaml
server:
  config:
    url: https://<ARGOCD_URL>
    dex.config: |
      connectors:
      - type: saml
        id: saml
        name: AzureAD
        config:
          entityIssuer: https://<ARGOCD_URL>/api/dex/callback
          ssoURL: https://login.microsoftonline.com/<TENANT_ID>/saml2
          caData: |
            <BASE64_ENCODED_CERTIFICATE>
          redirectURI: https://<ARGOCD_URL>/api/dex/callback
          usernameAttr: email
          emailAttr: email
          groupsAttr: Group

  rbacConfig:
    policy.default: role:readonly
    scopes: '[groups, email]'
    policy.csv: |
      p, role:admin, applications, *, */*, allow
      p, role:admin, clusters, *, *, allow
      p, role:admin, repositories, *, *, allow
      g, "<ADMIN_GROUP_OBJECT_ID>", role:admin
```

Deploy:

```bash
helm upgrade --install argocd argo/argo-cd -n argocd -f values.yaml
```

---

# Application 3: Jenkins

Jenkins uses the open-source **SAML Plugin** for SAML integration.

## Step 1: Install the Jenkins SAML Plugin

1. Log into Jenkins as admin
2. Go to **Manage Jenkins → Plugins → Available**
3. Search for `SAML`
4. Install **SAML Plugin** (by `jenkinsci`)
5. Restart Jenkins

---

## Step 2: Create Azure AD Enterprise Application

### 2.1 Create the Application

1. Go to **Azure Portal → Azure Active Directory → Enterprise Applications**
2. Click **+ New application → Create your own application**
3. Name: `Jenkins`
4. Select: **Integrate any other application you don't find in the gallery**
5. Click **Create**

### 2.2 Configure SAML SSO

1. Go to **Single sign-on → SAML**
2. Click **Edit** under **Basic SAML Configuration**
3. Enter:

| Field | Value |
|---|---|
| Identifier (Entity ID) | `JenkinsSP` |
| Reply URL (ACS URL) | `https://<JENKINS_URL>/securityRealm/finishLogin` |
| Sign on URL | `https://<JENKINS_URL>` |
| Sign-Out URL | `https://login.microsoftonline.com/common/wsfederation?wa=wsignout1.0` |

4. Click **Save**

### 2.3 Configure Attributes & Claims

Click **Edit** under **User Attributes & Claims**:

**Add new claims:**

| Claim Name | Source Attribute |
|---|---|
| `username` | `user.userprincipalname` |
| `displayname` | `user.displayname` |
| `email` | `user.mail` |

**Add a group claim:**

- Which groups: **Groups assigned to the application**
- Source attribute: **Group ID**
- Customize: **True**
- Name: `groups`
- Namespace: *(leave empty)*
- Emit groups as role claims: **False**

Click **Save**

### 2.4 Copy Federation Metadata URL

Under **Set up Jenkins**, copy the **App Federation Metadata URL**:

```
https://login.microsoftonline.com/<TENANT_ID>/federationmetadata/2007-06/federationmetadata.xml
```

### 2.5 Assign Users and Groups

1. Go to **Users and groups → + Add user/group**
2. Select users/groups that should access Jenkins
3. Click **Assign**

---

## Step 3: Configure Jenkins SAML Plugin

### 3.1 Navigate to Security Settings

1. Go to **Manage Jenkins → Security**
2. Under **Security Realm**, select **SAML 2.0**

### 3.2 Fill in SAML Configuration

| Field | Value |
|---|---|
| IdP Metadata URL | `https://login.microsoftonline.com/<TENANT_ID>/federationmetadata/2007-06/federationmetadata.xml` |
| Username Attribute | `username` |
| Display Name Attribute | `displayname` |
| Email Attribute | `email` |
| Group Attribute | `groups` |
| SP Entity ID | `JenkinsSP` (must match Azure Identifier) |
| Logout URL | `https://login.microsoftonline.com/common/wsfederation?wa=wsignout1.0` |
| Data Binding Method | `urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect` |

**Advanced Configuration:**
- Force Authentication: **Checked** (recommended)

Click **Save**

### 3.3 Configure Authorization

1. Under **Authorization**, select **Matrix-based security** or **Role-Based Strategy**
2. Add Azure AD Group Object IDs and assign permissions:

| Group | Permissions |
|---|---|
| `<ADMIN_GROUP_OBJECT_ID>` | Full Admin |
| `<DEPLOYER_GROUP_OBJECT_ID>` | Build, Cancel, Read jobs |
| `<READONLY_GROUP_OBJECT_ID>` | Read-only access |

3. Click **Save**

### 3.4 Test

1. Log out of Jenkins
2. Click the **SAML login** option
3. Authenticate with Azure AD credentials
4. Verify correct permissions

---

# Quick Reference Summary

## Entity IDs

| Application | Entity ID |
|---|---|
| Rancher | `https://<RANCHER_URL>/v1-saml/adfs/saml/metadata` |
| ArgoCD | `https://<ARGOCD_URL>/api/dex/callback` |
| Jenkins | `JenkinsSP` |

## Reply / ACS URLs

| Application | ACS URL |
|---|---|
| Rancher | `https://<RANCHER_URL>/v1-saml/adfs/saml/acs` |
| ArgoCD | `https://<ARGOCD_URL>/api/dex/callback` |
| Jenkins | `https://<JENKINS_URL>/securityRealm/finishLogin` |

## SAML Mechanism

| Application | How SAML is Handled |
|---|---|
| Rancher | Built-in ADFS auth provider |
| ArgoCD | Dex SAML connector (argocd-cm ConfigMap) |
| Jenkins | SAML Plugin (Manage Jenkins → Security) |

## Group Restriction

| Application | Where to Restrict |
|---|---|
| Rancher | Auth Provider → Site Access → Restrict to Authorized Users |
| ArgoCD | argocd-rbac-cm ConfigMap → policy.csv |
| Jenkins | Manage Jenkins → Security → Authorization (Matrix/Role) |

## Azure AD Claim Names Per Application

| Claim | Rancher | ArgoCD | Jenkins |
|---|---|---|---|
| Display Name | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name` | *(not used)* | `displayname` |
| Username | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname` | `email` | `username` |
| UID / Email | `http://schemas.xmlsoap.org/ws/2005/05/identity/claims/upn` | `email` | `email` |
| Groups | `http://schemas.xmlsoap.org/claims/Group` | `Group` | `groups` |

---

# Troubleshooting

## Common Issues

### "Redirect URI does not match"
The Reply URL in Azure must exactly match the application's ACS URL, including protocol and trailing slashes.

### "Groups not appearing after login"
1. Use **"Groups assigned to the application"** instead of "All groups" in Azure (avoids 150-group limit)
2. Ensure users are in groups that are assigned to the Enterprise Application
3. Verify claim attribute names match exactly between Azure and application config

### "Certificate validation failed"
- Re-download the certificate from Azure
- For ArgoCD: ensure proper Base64 encoding (`cat cert.cer | base64`)
- Check expiry: `openssl x509 -in cert.cer -noout -dates`

### "Authenticated but no permissions"
- Rancher: Check Site Access settings and add groups/users
- ArgoCD: Verify Group Object IDs in `argocd-rbac-cm` and that `scopes: '[groups, email]'` is set
- Jenkins: Add Group Object IDs in Matrix Authorization

## Debugging Commands

```bash
# ArgoCD - Check Dex logs
kubectl -n argocd logs deployment/argocd-dex-server

# ArgoCD - Check server logs
kubectl -n argocd logs deployment/argocd-server

# ArgoCD - Verify ConfigMaps
kubectl -n argocd get configmap argocd-cm -o yaml
kubectl -n argocd get configmap argocd-rbac-cm -o yaml

# Verify certificate
openssl x509 -in cert.cer -text -noout

# Decode a SAML response (from browser network tab)
echo "<base64-saml-response>" | base64 -d | xmllint --format -
```

---

# Reference Links

## Rancher
- Rancher AD FS SAML Configuration: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/authentication-permissions-and-global-configuration/configure-microsoft-ad-federation-service-saml
- Configuring Rancher for AD FS: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/authentication-permissions-and-global-configuration/configure-microsoft-ad-federation-service-saml/configure-rancher-for-ms-adfs
- Configuring AD FS for Rancher: https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/authentication-permissions-and-global-configuration/configure-microsoft-ad-federation-service-saml/configure-ms-adfs-for-rancher

## ArgoCD
- ArgoCD Official Microsoft/Entra ID Docs: https://argo-cd.readthedocs.io/en/latest/operator-manual/user-management/microsoft/
- ArgoCD RBAC Configuration: https://argo-cd.readthedocs.io/en/latest/operator-manual/rbac/
- ArgoCD SSO Overview: https://argo-cd.readthedocs.io/en/latest/operator-manual/user-management/

## Jenkins
- Jenkins SAML Plugin: https://plugins.jenkins.io/saml/
- Jenkins SAML Plugin GitHub: https://github.com/jenkinsci/saml-plugin
- Jenkins SAML Azure Configuration: https://github.com/jenkinsci/saml-plugin/blob/master/doc/CONFIGURE_AZURE.md
- Jenkins Security Docs: https://www.jenkins.io/doc/book/security/

## Azure AD / Entra ID
- Enterprise Application SSO: https://learn.microsoft.com/en-us/azure/active-directory/manage-apps/what-is-single-sign-on
- SAML Token Customization: https://learn.microsoft.com/en-us/azure/active-directory/develop/active-directory-saml-claims-customization
- Group Claims: https://learn.microsoft.com/en-us/azure/active-directory/hybrid/how-to-connect-fed-group-claims
- My Apps Portal: https://learn.microsoft.com/en-us/azure/active-directory/user-help/my-apps-portal-end-user-access

---

*End of Document*
