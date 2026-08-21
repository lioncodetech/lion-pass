import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController,
    UITableViewDataSource,
    UITableViewDelegate,
    UITextFieldDelegate {

    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let passwordField = UITextField()
    private let unlockButton = UIButton(type: .system)
    private let messageLabel = UILabel()
    private var decryptedItems: [VaultItem] = []
    private var requestedServices: [ASCredentialServiceIdentifier] = []
    private var requestedIdentity: ASPasswordCredentialIdentity?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Lion Pass"
        view.backgroundColor = .systemBackground

        passwordField.placeholder = "Senha mestra"
        passwordField.isSecureTextEntry = true
        passwordField.textContentType = .password
        passwordField.borderStyle = .roundedRect
        passwordField.returnKeyType = .go
        passwordField.delegate = self
        passwordField.accessibilityLabel = "Senha mestra"

        unlockButton.setTitle("Desbloquear cofre", for: .normal)
        unlockButton.addTarget(self, action: #selector(unlockVault), for: .touchUpInside)

        messageLabel.text = "O cofre é descriptografado somente após sua autenticação."
        messageLabel.textColor = .secondaryLabel
        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center

        table.dataSource = self
        table.delegate = self
        table.keyboardDismissMode = .onDrag

        let stack = UIStackView(arrangedSubviews: [passwordField, unlockButton, messageLabel, table])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        requestedServices = serviceIdentifiers
        requestedIdentity = nil
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        requestedIdentity = credentialIdentity
        requestedServices = [credentialIdentity.serviceIdentifier]
    }

    override func provideCredentialWithoutUserInteraction(
        for credentialIdentity: ASPasswordCredentialIdentity
    ) {
        // The encrypted vault must never be kept open by the extension.
        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        clearSensitiveState()
    }

    override func didReceiveMemoryWarning() {
        clearSensitiveState()
        super.didReceiveMemoryWarning()
    }

    @objc private func unlockVault() {
        guard let password = passwordField.text, password.isEmpty == false else { return }
        do {
            let result = try AppleVaultCryptoService().unlock(
                LocalVaultStorageService().readEncryptedVault(),
                password: password
            )
            passwordField.text = nil
            let logins = result.payload.items.filter { $0.kind == .login }
            if let requestedIdentity,
               let recordIdentifier = requestedIdentity.recordIdentifier,
               let item = logins.first(where: { $0.id.uuidString == recordIdentifier }) {
                complete(with: item)
                return
            }

            decryptedItems = filter(logins)

            passwordField.isHidden = true
            unlockButton.isHidden = true
            messageLabel.text = decryptedItems.isEmpty
                ? "Nenhuma credencial corresponde ao site solicitado."
                : "Selecione uma credencial."
            table.reloadData()
        } catch {
            passwordField.text = nil
            let alert = UIAlertController(
                title: "Não foi possível abrir",
                message: error.localizedDescription,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        unlockVault()
        return true
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        decryptedItems.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let identifier = "Credential"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier)
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let item = decryptedItems[indexPath.row]
        cell.textLabel?.text = item.title
        cell.detailTextLabel?.text = item.username
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        complete(with: decryptedItems[indexPath.row])
    }

    private func complete(with item: VaultItem) {
        let credential = ASPasswordCredential(user: item.username, password: item.password)
        clearSensitiveState()
        extensionContext.completeRequest(withSelectedCredential: credential, completionHandler: nil)
    }

    private func filter(_ items: [VaultItem]) -> [VaultItem] {
        let logins = items.filter { $0.kind == .login }
        guard requestedServices.isEmpty == false else { return logins }
        let requested = Set(requestedServices.compactMap(normalizedHost(for:)))
        guard requested.isEmpty == false else { return [] }
        return logins.filter { item in
            guard let host = normalizedWebsiteHost(item.website) else { return false }
            return requested.contains(host)
        }
    }

    private func normalizedHost(for service: ASCredentialServiceIdentifier) -> String? {
        switch service.type {
        case .domain:
            return normalizedDomain(service.identifier)
        case .URL:
            guard let host = URL(string: service.identifier)?.host else { return nil }
            return normalizedDomain(host)
        default:
            return nil
        }
    }

    private func normalizedWebsiteHost(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let host = URL(string: clean)?.host { return normalizedDomain(host) }
        if let host = URL(string: "https://\(clean)")?.host { return normalizedDomain(host) }
        return nil
    }

    private func normalizedDomain(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        guard clean.isEmpty == false,
              clean.contains("."),
              clean.utf8.count <= 253,
              clean.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                  label.isEmpty == false && label.utf8.count <= 63 &&
                      label.first != "-" && label.last != "-" &&
                      label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
              })
        else { return nil }
        return clean
    }

    private func clearSensitiveState() {
        passwordField.text = nil
        decryptedItems.removeAll(keepingCapacity: false)
        table.reloadData()
    }
}
