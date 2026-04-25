## Create Microsoft Entra External Tenant and Configure Application

0. Now let's configure the Microsoft Entra ID tenant needed for web app authentication.
1. Navigate to the **Microsoft Entra ID** blade in the Azure portal.
2. Select **Manage tenants** then **Create**
3. Select **External** then **Next**
4. Specify the **Organization Name**, **Initial Domain Name**, **Subscription**, and **Resource Group**.
5. Record the **Initial Domain Name** in the build environment variables.
6. Select **Review + create** and wait for the tenant deployment to complete.
7. Open the tenant resource group
8. Record the **Tenant ID** in the build environment variables.
9. Select **Switch directory**.
10. Switch to the new external tenant directory.

---

## Create User Flow

13. Select **Manage Microsoft Entra ID**
14. Select **External Identities**.
15. Select **Configure  User flows**.
16. Select **New user flow**.
17. Specify the **user flow name**.
18. Record the **User flow name** for later input into environment variables.
19. Select **Create** and wait for completion.

---

## Create App Registration

20. Navigate to **App registrations**.
21. Select **New registration**.
22. Specify the **application name**, then select **Register**.
23. Record the **Application (client) ID** for later input into environment variables.

---

## Create Client Secret

24. Select **Certificates & secrets**.
25. Select **New client secret**.
26. Specify a description, then select **Add**.
27. The secret value is displayed.
28. Record the **client secret value** for later input into environment variables.

---

## Configure API Permissions

30. Select **API permissions**.
31. Select **Add a permission**.
32. Select **Microsoft Graph**.
33. Select **Application permissions**.
34. Add the following Read Write permissions:
    - `EventListener.ReadWrite.All`
    - `Application.ReadWrite.All`
35. Select **Grant admin consent** and confirm the grants.
