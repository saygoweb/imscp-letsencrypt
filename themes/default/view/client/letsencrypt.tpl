
<!-- BDP: customer_list -->
<table>
    <thead>
    <tr>
        <th>{TR_STATUS}</th>
        <th>{TR_DOMAIN_NAME}</th>
        <th>{TR_HTTP_FORWARD}</th>
        <th>{TR_NOTE}</th>
        <th>{TR_ACTION}</th>
    </tr>
    </thead>
    <tbody>
    <!-- BDP: domainkey_item -->
    <tr>
        <td><div class="icon i_{STATUS_ICON}">{STATUS}<div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td>{HTTP_FORWARD}</td>
        <td>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td>    </tr>
    <!-- EDP: domainkey_item -->
    </tbody>
</table>
<!-- EDP: customer_list -->

