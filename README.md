# 🚀 Veeam Backup & Replication to Rocket.Chat Webhook Notifier

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg?logo=powershell)
![Veeam](https://img.shields.io/badge/Veeam%20B%26R-v11%20%7C%20v12%2B-00b336.svg)
![Rocket.Chat](https://img.shields.io/badge/Rocket.Chat-Webhook-f5455c.svg?logo=rocketchat)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

A lightweight, dependency-free PowerShell post-job script for **Veeam Backup & Replication (v11 & v12+)** that sends real-time, rich, color-coded backup status notifications and VM task details directly to **Rocket.Chat** via incoming webhooks.

---

## ✨ Features

* **Veeam v12+ Post-Job Bug Workaround:** In Veeam B&R, post-job scripts execute while the main backup session is technically still in a `Working` state (which normally returns `None` as the final result). This script inspects individual **VM Task Sessions** directly to determine the exact final status (`Success`, `Warning`, or `Failed`).
* **Color-Coded Attachments:**
  * 🟢 **Success** (`#2ecc71`)
  * 🟠 **Warning** (`#f39c12`)
  * 🔴 **Failed** (`#e74c3c`)
* **Detailed Metrics:** Reports job duration, processed data size (GB), actual transferred size (GB), and a summary count of succeeded, warning, and failed VMs.
* **Granular Error Reporting:** Automatically extracts the exact failure or warning reasons per VM/Task and strips HTML tags (`<br />`) for clean rendering in Rocket.Chat.
* **Clock-Drift / Future Date Protection:** Filters out corrupted or future-dated sessions (`Year < 2040`) caused by accidental Windows Server time/timezone changes.
* **Fail-Safe Execution:** Wrapped in a `try/catch` block with local error logging (`Veeam-Webhook-Error.log`) so network or webhook issues never cause your actual Veeam backup job to fail or hang.

---

## 📸 Message Preview

When a backup job finishes, the script posts an attachment to your Rocket.Chat channel containing:

> ✅ **Veeam Backup Report: Production-VMs**
> * **Status:** Success | **Duration:** 00:38:12
> * **Processed Size:** 450.25 GB | **Transferred:** 18.40 GB
> * **VM Summary:** Success: 4 | Warning: 0 | Failed: 0
> * **Details:** All 4 VM(s)/Task(s) processed successfully.
> * *Veeam B&R on VEEAM-SRV01 | Started: 2026-11-05 06:00:00*

---

## 🛠️ Setup & Installation

### Step 1: Create an Incoming Webhook in Rocket.Chat
1. Go to **Administration** -> **Workspace** -> **Integrations**.
2. Click **New** at the top right and select the **Incoming** tab.
3. Turn on **Enabled**.
4. Give it a **Name** (e.g., `Veeam Backup Alert`).
5. Select your target channel or private group in **Post to Channel** (e.g., `#alerts` or `@username`).
6. Set **Post as** to an existing user or bot (e.g., `rocket.cat`).
7. Click **Save** and copy the generated **Webhook URL**.

### Step 2: Configure the Script on the Veeam Server
1. Download `Veeam-RocketChat.ps1` and place it on your Veeam Backup Server (e.g., `C:\Veeam-RocketChat.ps1`).
2. Open `Veeam-RocketChat.ps1` in a text editor and replace the `$WebhookUrl` variable on **Line 6** with your Rocket.Chat Webhook URL:
   ```powershell
   $WebhookUrl = "https://YOUR_ROCKETCHAT_DOMAIN/hooks/YOUR_TOKEN_HERE"
   ```
   *(Important: Save the file with **UTF-8 with BOM** encoding to ensure emojis render properly in Windows PowerShell).*
3. Open **PowerShell as Administrator** on the Veeam server and unblock the script:
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
   Unblock-File -Path "C:\Veeam-RocketChat.ps1"
   ```

### Step 3: Attach the Script to Your Veeam Backup Job(s)
1. Open the **Veeam Backup & Replication Console**.
2. Right-click on your Backup Job and select **Edit**.
3. Navigate to the **Storage** tab and click **Advanced...**.
4. Go to the **Scripts** tab.
5. Check **Run the following script after the job** and enter the following command:
   ```text
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Veeam-RocketChat.ps1"
   ```
6. Make sure **Run scripts every...** is set to `1 backup session`.
7. Click **OK** and **Finish** to save the job settings.

---

## 🔍 Troubleshooting

* **No message received in Rocket.Chat:** Check the `Veeam-Webhook-Error.log` file generated in the same directory as `Veeam-RocketChat.ps1`.
* **`Unable to connect to the server with MFA-enabled user account` error:** This happens if you run the script manually inside an interactive PowerShell session using a Windows user account that has MFA enabled in the Veeam Console. When Veeam executes the post-job script automatically at the end of a backup job, it runs under the `NT AUTHORITY\SYSTEM` service account, which bypasses interactive MFA restrictions.

---

## 📄 License

This project is licensed under the **MIT License** — feel free to use, modify, and distribute it as needed.
