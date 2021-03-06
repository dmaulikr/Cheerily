//
//  OauthClient.swift
//  Cheerily
//
//  Created by Roman Sheydvasser on 5/2/17.
//  Copyright © 2017 RLabs. All rights reserved.
//

import Foundation
import Alamofire

extension WebClient {
    
    func parseRedirectUri(_ uri: URL) {
        if let code = getValueFromUrlParameter(url: uri.absoluteString, parameter: "code"),
            let state = getValueFromUrlParameter(url: uri.absoluteString, parameter: "state"),
            state == tempState {
            self.authCode = code
            UserDefaults.standard.set(code, forKey: "authCode")
        } else {
            Helper.displayAlertOnMain("Redirect URI did not contain expected values.")
        }
    }
    
    func createRandomState() -> String? {
        tempState = String.random()
        return tempState
    }
    
    func getRedditAuthUrl() -> String? {
        if let randomState = createRandomState() {
            let authUrl = "\(Constants.redditBaseAuthUrl)client_id=\(Constants.redditClientId)&response_type=code&state=\(randomState)&redirect_uri=\(Constants.redditRedirectUri)&duration=permanent&scope=read"
            print("Auth URL created: \(authUrl)")
            return authUrl
        } else {
            return nil
        }
    }
    
    func requestAccessToken(completionHandler: @escaping (_ success: Bool) -> Void) {
        guard let authCode = UserDefaults.standard.value(forKey: "authCode") as? String else {
            print("No auth code exists.")
            completionHandler(false)
            return
        }
        
        let parameters: Parameters = [
            "grant_type": "authorization_code",
            "code": authCode,
            "redirect_uri": Constants.redditRedirectUri
        ]
        
        print("parameters are \(parameters)")
        
        Alamofire.request(Constants.redditAccessTokenUrl, method: .post,
                          parameters: parameters, encoding: URLEncoding.httpBody)
            .authenticate(user: Constants.redditClientId, password: "")
            .responseJSON { response in
                
                guard let JSON = response.result.value as? [String:Any] else {
                    print("Response data was not valid JSON.")
                    return
                }
                
                guard let accessToken = JSON["access_token"] as? String,
                    let refreshToken = JSON["refresh_token"] as? String else {
                        print("Response JSON did not contain token values.")
                        completionHandler(false)
                        return
                }
                
                UserDefaults.standard.setValue(accessToken, forKey: "accessToken")
                UserDefaults.standard.setValue(refreshToken, forKey: "refreshToken")
                self.accessToken = accessToken
                self.refreshToken = refreshToken
                
                self.sessionManager.adapter =
                    AccessTokenAdapter(accessToken: accessToken,
                                       forBaseUrl: Constants.redditTokenBaseUrl)
                
                print("JSON: \(JSON)")
                completionHandler(true)
        }
    }
    
    func renewToken(completionHandler: @escaping () -> Void) {
        
        guard let refreshToken = refreshToken else {
            print("No refresh token available.")
            
            return
        }
        
        let parameters: Parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        
        Alamofire.request(Constants.redditAccessTokenUrl, method: .post,
                          parameters: parameters, encoding: URLEncoding.httpBody)
            .authenticate(user: Constants.redditClientId, password: "")
            .responseJSON { response in
                print("result: \(response.result)")
                
                guard let JSON = response.result.value as? [String:Any] else {
                    print("Response data was not valid JSON.")
                    return
                }
                
                guard let accessToken = JSON["access_token"] as? String else {
                    print("Response JSON did not contain token value.")
                    return
                }
                
                self.accessToken = accessToken
                UserDefaults.standard.setValue(accessToken, forKey: "accessToken")
                print("Token renewed.")
                completionHandler()
        }
    }
    
    func revokeToken(completionHandler: @escaping (_ success: Bool) -> Void) {
        
        print("Trying to revoke token.")
        
        guard let refreshToken = refreshToken else {
            print("No refresh token available.")
            return
        }
        
        let parameters: Parameters = [
            "token": refreshToken
        ]
        
        Alamofire.request(Constants.redditRevokeTokenUrl, method: .post,
                          parameters: parameters, encoding: URLEncoding.httpBody)
            .authenticate(user: Constants.redditClientId, password: "")
            .response { response in
                if let httpStatusCode = response.response?.statusCode,
                    httpStatusCode == 204 {
                        print("HTTP Status Code: \(httpStatusCode)")
                        print("Token revoked.")
                        UserDefaults.standard.removeObject(forKey: "refreshToken")
                        self.refreshToken = nil
                        completionHandler(true)
                } else {
                    print("Invalid response/Http status code was not 204.")
                    completionHandler(false)
                    return
                }
        }
    }

    
    func checkForToken(completionHandler: @escaping (_ exists: Bool) -> Void) {
        if let accessToken = UserDefaults.standard.value(forKey: "accessToken") as? String,
            let refreshToken = UserDefaults.standard.value(forKey: "refreshToken") as? String {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            completionHandler(true)
        } else {
            requestAccessToken() { success in
                if success {
                    completionHandler(true)
                } else {
                    completionHandler(false)
                }
            }
        }
    }
}
