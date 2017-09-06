<h3 class="domains"><span>{TR_DOMAINS}</span></h3>

<!-- BDP: domain_list -->
<table class="firstColFixed">
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
    <!-- BDP: domain_item -->
    <tr>
        <td><div class="icon i_{STATUS_ICON}">{STATUS}<div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td>{HTTP_FORWARD}</td>
        <td>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td></tr>
    <!-- EDP: domain_item -->
    </tbody>
</table>
<!-- EDP: domains_list -->

<!-- BDP: domain_aliases_block -->
<h3 class="domains"><span>{TR_DOMAIN_ALIASES}</span></h3>
<!-- BDP: als_message -->
<div class="static_info">{ALS_MSG}</div>
<!-- EDP: als_message -->
<!-- BDP: als_list -->
<table class="firstColFixed datatable">
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
    <!-- BDP: als_item -->
    <tr>
        <td><div class="icon i_{STATUS_ICON}">{STATUS}<div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td>{HTTP_FORWARD}</td>
        <td>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td></tr>
    <!-- EDP: als_item -->
    </tbody>
</table>
<!-- EDP: als_list -->
<!-- EDP: domain_aliases_block -->

<!-- BDP: subdomains_block -->
<h3 class="domains"><span>{TR_SUBDOMAINS}</span></h3>
<!-- BDP: sub_message -->
<div class="static_info">{SUB_MSG}</div>
<!-- EDP: sub_message -->
<!-- BDP: sub_list -->
<table class="firstColFixed datatable">
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
    <!-- BDP: sub_item -->
    <tr>
        <td><div class="icon i_{STATUS_ICON}">{STATUS}<div></td>
        <td><label for="keyid_{ID}">{DOMAIN_NAME}</label></td>
        <td>{HTTP_FORWARD}</td>
        <td>{NOTE}</td>
        <td>
            <a class="icon i_edit" href="{EDIT_LINK}" title="{EDIT}">{EDIT}</a>
        </td></tr>
    <!-- EDP: sub_item -->
    </tbody>
</table>
<!-- EDP: sub_list -->
<!-- EDP: subdomains_block -->
