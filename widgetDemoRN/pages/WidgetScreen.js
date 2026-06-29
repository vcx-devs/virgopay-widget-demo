import React, { useRef } from "react";
import { View, Alert, Text } from "react-native";
import { WebView } from "react-native-webview";
import { Linking } from 'react-native';

const ENCRYPTED_ADRRESS_STRING = "your_encrypted_address_string";
const YOUR_LOGO_URL = 'your_logo_url';
const NONCE = 'your_nonce';

export default function WidgetScreen() {
    const webRef = useRef(null);
    const uri = "https://sandbox.virgopay.co/page#/widget/login?type=1&code=your_code";

    const openLink = async (url) => {
        try {
            
            const ok = await Linking.canOpenURL(url);
            console.log(ok,'Opening URL:', url);
            // if (!ok) throw new Error('cannot open url');
            await Linking.openURL(url); // iOS -> Safari，Android -> device's browser
        } catch (e) {
            Alert.alert('Unable to open link', String(e));
        }
    }

    const postToWeb = (type, payload = {}) => {
        webRef.current?.postMessage(
            JSON.stringify({
                type,
                payload,
            })
        );
    };

    const config = {
        host: "virgopay",
        theme: 'dark',
        primaryColor: '#6b47ed',
        isMobileApp: true,
        logoUrl: "original" || YOUR_LOGO_URL,
        addressInfo: ENCRYPTED_ADRRESS_STRING || null,
        nonce: NONCE || "",
    };

    const safeParse = (raw) => {
        if (!raw) return null;

        // Already an object (rare, RN usually receives string)
        if (typeof raw === "object") return raw;

        if (typeof raw !== "string") return null;

        // Common bad case when postMessage receives object instead of string
        if (raw === "[object Object]") return null;

        try {
            return JSON.parse(raw);
        } catch {
            return null;
        }
    };

    const normalizeMsg = (msg) => {
        if (!msg) return null;

        // Compatible with wrapped message format: { type: "message", data/payload: ... }
        if (msg.type === "message") {
            return safeParse(msg.data) || safeParse(msg.payload) || msg;
        }

        return msg;
    };

    

    const onMessage=(event)=>{
        const raw = event?.nativeEvent?.data;
        const parsed = normalizeMsg(safeParse(raw));
        if (!parsed) return;

        const { type, payload } = parsed;

        switch (type) {
            // ====== Handshake / Config passing======
            case "REQUEST_CONFIG":
            case "PING": {
                postToWeb("WIDGET_CONFIG", config);
                break;
            }

            // ====== Business Messages ======
            case "TRANSACTION_ID": {
                // Example: payload.id
                alert(payload?.id, "TRANSACTION_ID");
                break;
            }

            case "OPEN_LINK": {
                // payload.url
                if (payload?.url) openLink(payload.url);
                break;
            }

            case "TRANSACTION_FUND": {
                //Upon receiving this message, it indicates that the user has confirmed the payment and completed all required steps. The widget host may then proceed with any post-transaction actions, such as closing the widget and redirecting the user to the host’s designated page.
                break;
            }

            case "MAIL_TO": {
                // payload.url (mailto:xxx@xx.com?subject=...)
                alert(payload?.url, "mail url");
                // You can also do: openLink(payload.url)
                break;
            }

            case "CUSTOMER_ID": {
                // payload.customerId
                // alert(payload?.customerId, 'customerId')
                break;
            }

            case "NONCE": {
                alert(payload?.nonce, "nonce");
                //store this NONCE in host side to enhance user login experience.
                break;
            }

            case "LOG_OUT": {
                //user log out from widget, remove NONCE(if exist)
                break;
            }

            default: {
                alert(`Unhandled message type: ${type}`);
                break;
            }
        }
    }

    return (
        <View style={{ flex: 1, }}>
            <WebView
                ref={WebView => webRef.current = WebView}
                source={{ uri: uri }}
                onMessage={onMessage}
                onLoadEnd={() => postToWeb("PING", {})} // Trigger handshake after WebView load to sync config
                javaScriptEnabled
                style={{ backgroundColor: '#18304C', flex: 1, }} //need to pass a default color code
            />
        </View>
    );
}