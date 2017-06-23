
<!-- BDP: customer_list -->
<table>
    <thead>
    <tr>
        <th>{TR_STATUS}</th>
        <th>{TR_DOMAIN_NAME}</th>
        <th>{TR_ENABLED}</th>
        <th>{TR_NOTE}</th>
    </tr>
    </thead>
    <tbody>
    <!-- BDP: domainkey_item -->
    <tr>
        <td><div class="icon i_{STATUS_ICON}">{STATUS}<div></td>
        <td><label for="keyid_{LETSENCRYPT_ID}">{DOMAIN_NAME}</label></td>
        <td>{LETSENCRYPT_ENABLED}</td>
        <td>{LETSENCRYPT_NOTE}</td>
    </tr>
    <!-- EDP: domainkey_item -->
    </tbody>
</table>
<!-- EDP: customer_list -->
