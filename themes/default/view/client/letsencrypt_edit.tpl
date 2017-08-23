
<form name="letsencrypt_edit_frm" method="post" action="letsencrypt_edit.php?type={TYPE}&id={ID}">
    <table class="firstColFixed">
        <thead>
        <tr>
            <th colspan="2">{TR_DOMAIN}</th>
        </tr>
        </thead>
        <tbody>
        <tr>
            <td><label for="domain_name">{TR_DOMAIN_NAME}</label></td>
            <td>
                <span class="bold">www.</span>
                <input type="text" name="domain_name" id="domain_name" value="{DOMAIN_NAME}" readonly="readonly">
            </td>
        </tr>
        <tr>
            <td>
                {TR_ENABLED}
                <span class="icon i_help" title="{TR_ENABLED_TOOLTIP}"></span>
            </td>
            <td>
                <div class="radio">
                    <input type="radio" name="enabled" id="enabled_yes"{ENABLED_YES} value="yes">
                    <label for="enabled_yes">{TR_YES}</label>
                    <input type="radio" name="enabled" id="enabled_no"{ENABLED_NO} value="no">
                    <label for="enabled_no">{TR_NO}</label>
                </div>
            </td>
        </tr>
        <tr>
            <td>
                {TR_HTTP_FORWARD}
                <span class="icon i_help" title="{TR_HTTP_FORWARD_TOOLTIP}"></span>
            </td>
            <td>
                <div class="radio">
                    <input type="radio" name="http_forward" id="http_forward_yes"{HTTP_FORWARD_YES} value="yes">
                    <label for="http_forward_yes">{TR_YES}</label>
                    <input type="radio" name="http_forward" id="http_forward_no"{HTTP_FORWARD_NO} value="no">
                    <label for="http_forward_no">{TR_NO}</label>
                </div>
            </td>
        </tr>
        </tbody>
    </table>
    <div class="buttons">
        <input name="Submit" type="submit" value="{TR_UPDATE}">
        <a class="link_as_button" href="letsencrypt.php">{TR_CANCEL}</a>
    </div>
</form>
