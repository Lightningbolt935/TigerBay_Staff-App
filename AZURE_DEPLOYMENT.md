# 🚀 TigerBay Staff App — Production Azure & Release Deployment Guide

This guide provides instructions for deploying the TigerBay Staff App to **Microsoft Azure** (Static Web Apps / Azure Container Apps) and building release bundles for **Android** and **iOS**.

---

## 1. Overview & Cloud Architecture

```
                          ┌──────────────────────────┐
                          │   GitHub Actions CI/CD   │
                          │ (.github/workflows/*.yml)│
                          └─────────────┬────────────┘
                                        │
                 ┌──────────────────────┼──────────────────────┐
                 ▼                      ▼                      ▼
        ┌─────────────────┐   ┌──────────────────┐   ┌──────────────────┐
        │  Android Release │   │   iOS Release    │   │  Staff Web Portal│
        │  (.apk & .aab)  │   │  (Xcode Archive) │   │   (SPA Container)│
        └─────────────────┘   └──────────────────┘   ─────────┬────────┘
                                                               │
                                         ┌─────────────────────┴────────────────────┐
                                         ▼                                          ▼
                              ┌──────────────────────┐                  ┌──────────────────────┐
                              │ Azure Static Web App │  (OR)            │ Azure Container App  │
                              │ (Global Edge / CDN)  │                  │ (Nginx / Linux App)  │
                              └──────────────────────┘                  └──────────────────────┘
```

---

## 2. GitHub Secrets Setup

Navigate to your GitHub repository:
**Settings** → **Secrets and variables** → **Actions** → Add the following secrets:

| Secret Name | Description | Required For |
| :--- | :--- | :--- |
| `SUPABASE_URL` | Supabase Project API URL | Web & Mobile Builds |
| `SUPABASE_ANON_KEY` | Supabase Public Anon JWT Key | Web & Mobile Builds |
| `AZURE_STATIC_WEB_APPS_API_TOKEN` | Azure SWA Deployment Token | Azure Static Web Apps |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoded `.jks` release keystore | Production Android Release |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password | Production Android Release |
| `ANDROID_KEY_ALIAS` | Release key alias | Production Android Release |
| `ANDROID_KEY_PASSWORD` | Key alias password | Production Android Release |

---

## 3. Deployment Option A: Azure Static Web Apps

1. **Create SWA Resource in Azure Portal**:
   - Search **Static Web Apps** → **Create**.
   - Select Subscription, Resource Group, Name (`tigerbay-staff-web`).
   - Plan: Standard or Free.
   - Region: Select nearest primary region (e.g. `West Europe` or `East US 2`).
2. **Retrieve Deployment Token**:
   - In Azure Portal resource page, click **Manage deployment token** and copy the secret.
3. **Configure GitHub Actions Secret**:
   - Save the token in GitHub repository secrets as `AZURE_STATIC_WEB_APPS_API_TOKEN`.
4. **Push to `main`**:
   - Pushing to `main` automatically builds Flutter Web with production optimizations and deploys to Azure Static Web Apps.

---

## 4. Deployment Option B: Azure App Service / Container Apps (Docker)

To deploy as a containerized web portal:

```bash
# 1. Build Docker image
docker build -t tigerbay-staff-app:latest \
  --build-arg SUPABASE_URL="https://your-project-ref.supabase.co" \
  --build-arg SUPABASE_ANON_KEY="eyJhbGci..." .

# 2. Test locally
docker run -p 8080:80 tigerbay-staff-app:latest

# 3. Push to Azure Container Registry (ACR)
az acr login --name <your_acr_name>
docker tag tigerbay-staff-app:latest <your_acr_name>.azurecr.io/tigerbay-staff-app:latest
docker push <your_acr_name>.azurecr.io/tigerbay-staff-app:latest
```

---

## 5. Mobile Release Builds (Android & iOS)

### Android Release APK / AAB
```bash
# Build release APK
flutter build apk --release

# Build Android App Bundle for Google Play
flutter build appbundle --release
```
*Note: R8 Proguard rules in `android/app/proguard-rules.pro` protect MLKit barcode scanner and CameraX classes from obfuscation issues.*

### iOS Release Build
```bash
flutter build ipa --release
```
