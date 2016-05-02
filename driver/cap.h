

typedef struct t_handshake {
	char bssid[6];  // AP's MAC
	char assid[6];  // Clients's MAC
	
	char anonce[32]; // AP's nonce
	char snonce[32]; // Client's nonce

	char eapol[256]; // EAPOL packet (MIC zeroed out!)
	char mic  [16];  // MIC

	char essid[256];  // SSID

	int eapol_len;
} t_handshake;

int parse_pcap(const char * pcap_file, t_handshake * hs, std::string desired_bssid);


