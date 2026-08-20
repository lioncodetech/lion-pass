import AuthenticationServices
import UIKit

final class CredentialProviderViewController: ASCredentialProviderViewController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let passwordField = UITextField(); private var items: [VaultItem] = []

    override func viewDidLoad() {
        super.viewDidLoad(); title = "Lion Password"; view.backgroundColor = .systemBackground
        passwordField.placeholder = "Senha mestra"; passwordField.isSecureTextEntry = true; passwordField.textContentType = .password; passwordField.borderStyle = .roundedRect
        let unlock = UIButton(type: .system); unlock.setTitle("Desbloquear cofre", for: .normal); unlock.addTarget(self, action: #selector(unlockVault), for: .touchUpInside)
        table.dataSource = self; table.delegate = self; table.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [passwordField, unlock, table]); stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }

    @objc private func unlockVault() {
        guard let password = passwordField.text else { return }
        do { let result = try AppleVaultCryptoService().decrypt(LocalVaultStorageService().readEncryptedVault(), password: password); items = result.0.items.filter { $0.kind == .login }; passwordField.text = nil; passwordField.removeFromSuperview(); table.reloadData() }
        catch { let alert = UIAlertController(title: "Não foi possível abrir", message: error.localizedDescription, preferredStyle: .alert); alert.addAction(UIAlertAction(title: "OK", style: .default)); present(alert, animated: true) }
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { items.count }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell { let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil); let item = items[indexPath.row]; cell.textLabel?.text = item.title; cell.detailTextLabel?.text = item.username; cell.accessoryType = .disclosureIndicator; return cell }
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { let item = items[indexPath.row]; extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: item.username, password: item.password), completionHandler: nil); items.removeAll() }
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) { }
    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) { extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired)) }
}
