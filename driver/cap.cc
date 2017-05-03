
// Cap parsing to extract EAPOL packets

#include <iostream>
#include <string.h>
#include <pcap.h>
#include "cap.h"

static std::string hexify(const char *in, int inlen) {
	std::string bin(in, inlen);

	std::string ret;
	for (auto c: bin) {	
		const char h[] = "0123456789abcdef";
		ret += h[(c>>4)&0xf];
		ret += h[c&0xf];
	}
	return ret;
}

int parse_pcap(const char * pcap_file, t_handshake * hs, std::string desired_bssid) {
	
	char errbuf[PCAP_ERRBUF_SIZE];
	pcap_t *handle = pcap_open_offline(pcap_file, errbuf);

	int ok = 0;
	struct pcap_pkthdr header;
	const unsigned char *packet;
	while (packet = pcap_next(handle, &header)) {
		// 802.11 dissect
		int ds_status = packet[1] & 0x3;

		if (packet[0] == 0x50 && header.caplen >= 26 + 14) {
			// Header size is 24 or 30 bytes  // FROM,TO
			int h80211_len = ds_status == 0x3 ? 30 : 24;

			const unsigned char *lnkmgt_header = &packet[h80211_len];
			const unsigned char *ssid_params = &lnkmgt_header[12];
			int ssid_num = ssid_params[0];
			int ssid_len = ssid_params[1];
			
			if (desired_bssid == hexify((char*)&packet[10], 6)) {
				memset(hs->essid, 0, sizeof(hs->essid));
				memcpy(hs->essid, &ssid_params[2], ssid_len);
				ok |= 4;
			}
		}
		if (packet[0] == 0x88 && header.caplen >= 26 + 8 + 9) {
			// Header size is 26 or 32 bytes  // FROM,TO
			int h80211_len = ds_status == 0x3 ? 32 : 26;

			const unsigned char *llc_header = &packet[h80211_len];
			// Check EAPOL
			if (llc_header[6] == 0x88 && llc_header[7] == 0x8E) {
				const unsigned char *auth_header = &llc_header[8];
				int eapol_len = (auth_header[2] << 8) + (auth_header[3]) + 4; 

				// Check EAPOL stuff
				if (auth_header[1] != 0x3) {
					std::cerr << "Key is not SHA1! Time to implement MD5?" << std::endl;
					continue;
				}
				if (auth_header[4] != 0x2 && auth_header[4] != 254) {
					std::cerr << "Non-WPA auth! (WPA/RSN)" << std::endl;
					continue;
				}
				int msg_n = 0;
				if ( (auth_header[5] & 0x01) == 0x00 &&  // MIC = 0
				     (auth_header[6] & 0x80) == 0x80 &&  // ACK = 1
				     (auth_header[6] & 0x40) == 0x00 &&  // Install = 0
				     (auth_header[6] & 0x08) == 0x08 )   // Pairwise = 1
					msg_n = 1;
				if ( (auth_header[5] & 0x01) == 0x01 &&  // MIC = 1
				     (auth_header[6] & 0x80) == 0x00 &&  // ACK = 0
				     (auth_header[6] & 0x40) == 0x40 &&  // Install = 0
				     (auth_header[6] & 0x08) == 0x08 )   // Pairwise = 1
					msg_n = 2;

				if (msg_n == 1) {
					// Copy AP's nonce
					memcpy(hs->anonce, &auth_header[17], 32);

					ok |= 1;
				}else{
					if (desired_bssid == hexify((char*)&packet[ 4], 6)) {
						// Copy MAC addr
						memcpy(hs->bssid, &packet[ 4], 6);
						memcpy(hs->assid, &packet[10], 6);

						// Copy Client's nonce
						memcpy(hs->snonce, &auth_header[17], 32);

						// Copy EAPOL
						memcpy(hs->eapol, auth_header, eapol_len);
						hs->eapol_len = eapol_len;
						memset(&hs->eapol[81], 0, 16); // Zero out MIC!

						// Copy MIC
						memcpy(hs->mic, &auth_header[81], 16);

						ok |= 2;
					}
				}
			}
		}

		if (ok == 7) break;
	}

	pcap_close(handle);

	if (ok == 7) {
		std::cerr << "Got handshake for BSSID " << hexify(hs->bssid, 6);
		std::cerr << " and client " << hexify(hs->assid, 6) << std::endl;

		std::cerr << "SNonce is " << hexify(hs->snonce, 32) << std::endl;
		std::cerr << "ANonce is " << hexify(hs->anonce, 32) << std::endl;

		std::cerr << "MIC is " << hexify(hs->mic, 16) << std::endl;
		std::cerr << "EAPOL is " << hexify(hs->eapol, hs->eapol_len) << std::endl;
	}

	return (ok == 7);
}

