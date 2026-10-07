import { useEffect, useState } from 'react';
import { api, projectRoleErrorMessage } from './api';

const projectRoles = ['PROJECT_MANAGER', 'TEAM_LEAD', 'CONTRIBUTOR', 'VIEWER'];

type Props = {
  projectId: string;
  userId: string;
  memberName: string;
  organizationRole?: string;
  role: string;
  canEdit: boolean;
  canGrantManager: boolean;
  isSelf: boolean;
  onSaved: () => void;
};

export function ProjectMemberRoleControl({ projectId, userId, memberName, organizationRole, role, canEdit, canGrantManager, isSelf, onSaved }: Props) {
  const [value, setValue] = useState(role);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  useEffect(() => setValue(role), [role]);

  if (!organizationRole) return <span>{role}</span>;
  if (organizationRole === 'GUEST') return <span aria-label={`Role for ${memberName}`}>VIEWER</span>;
  if (!canEdit || (isSelf && role !== 'PROJECT_MANAGER')) return <span>{role}</span>;

  const options = projectRoles.filter(option =>
    (canGrantManager || option !== 'PROJECT_MANAGER') && (!isSelf || option !== 'PROJECT_MANAGER' || role === 'PROJECT_MANAGER'));
  if (!options.includes(role)) options.unshift(role);

  const update = async (nextRole: string) => {
    if (nextRole === role || busy) return;
    setValue(nextRole);
    setError('');
    setBusy(true);
    try {
      await api.patch(`/projects/${projectId}/members/${userId}`, { role: nextRole });
      onSaved();
    } catch (requestError) {
      setValue(role);
      setError(projectRoleErrorMessage(requestError));
    } finally {
      setBusy(false);
    }
  };

  return <div className="project-role-control">
    <select aria-label={`Project role for ${memberName}`} value={value} disabled={busy} onChange={event => void update(event.target.value)}>
      {options.map(option => <option key={option} value={option}>{option.replace(/_/g, ' ')}</option>)}
    </select>
    {error && <small className="project-role-error" role="alert">{error}</small>}
  </div>;
}
