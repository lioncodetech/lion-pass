Name:           lion-pass
Version:        1.0.0
Release:        1%{?dist}
Summary:        Gerenciador de senhas local e offline
License:        Proprietary
URL:            https://lioncodetech.com.br/
Source0:        LionPass-Linux-linux-x64.tar.gz
Source1:        linux-pass.desktop
Source2:        lion-pass.png
Requires:       libX11, libICE, libSM, fontconfig
Recommends:     libsecret

%description
Lion Pass protege credenciais em cofres criptografados compatíveis com Apple e Windows.

%prep
%setup -q -c -T
tar -xzf %{SOURCE0}

%install
mkdir -p %{buildroot}/opt/lion-pass
cp -a publish/. %{buildroot}/opt/lion-pass/
install -Dm644 %{SOURCE1} %{buildroot}%{_datadir}/applications/lion-pass.desktop
install -Dm644 %{SOURCE2} %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/lion-pass.png

%files
/opt/lion-pass
%{_datadir}/applications/lion-pass.desktop
%{_datadir}/icons/hicolor/512x512/apps/lion-pass.png

%changelog
* Fri Aug 21 2026 Lion Code Technology <contato@lioncodetech.com.br> - 1.0.0-1
- Primeira versão Linux
